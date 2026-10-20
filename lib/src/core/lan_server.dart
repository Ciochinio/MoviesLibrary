import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'app_state.dart';
import 'lan_cert.dart';
import 'library_folders.dart';
import 'models.dart';
import 'thumbnail_service.dart';

/// Phone access settings. Machine-specific, so they live next to the executable
/// (like global_settings.json) rather than travelling with the Library.
class LanSettings {
  final bool enabled;
  final int port;
  final String pin;
  /// Random per-install secret the login token is derived from.
  final String secret;

  const LanSettings({required this.enabled, required this.port, required this.pin, required this.secret});

  static File get _file => File(p.join(p.dirname(Platform.resolvedExecutable), 'lan_settings.json'));

  static Future<LanSettings> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return LanSettings(
        enabled: j['enabled'] as bool? ?? false,
        port: j['port'] as int? ?? 8642,
        pin: j['pin'] as String? ?? '',
        secret: j['secret'] as String? ?? _randomHex(),
      );
    } catch (_) {
      return LanSettings(enabled: false, port: 8642, pin: '', secret: _randomHex());
    }
  }

  Future<void> save() => _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'enabled': enabled, 'port': port, 'pin': pin, 'secret': secret}));

  LanSettings copyWith({bool? enabled, int? port, String? pin}) =>
      LanSettings(enabled: enabled ?? this.enabled, port: port ?? this.port, pin: pin ?? this.pin, secret: secret);

  /// Login token for the current PIN; changing the PIN logs every phone out.
  String get token => sha256.convert(utf8.encode('$secret:$pin')).toString();

  static String _randomHex() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

class LanServerStatus {
  final bool running;
  final List<String> urls;
  /// Secure addresses (port + 1); needed for head tracking on iOS.
  final List<String> secureUrls;
  final String? error;
  const LanServerStatus({this.running = false, this.urls = const [], this.secureUrls = const [], this.error});
}

/// Small HTTP server that lets a phone on the home network browse and stream
/// the library. Only answers private-network addresses and requires the PIN.
class LanServer {
  LanServer._();
  static final instance = LanServer._();

  final status = ValueNotifier(const LanServerStatus());
  HttpServer? _server;
  HttpServer? _secureServer;
  LanCert? _cert;
  AppState? _app;
  LanSettings? _settings;

  /// Thumbnails being generated, so parallel requests for one item share the work.
  final Map<String, Future<bool>> _thumbJobs = {};
  /// Generation runs one ffmpeg at a time; a phone asks for dozens at once.
  Future<void> _thumbQueue = Future.value();

  int _failedLogins = 0;
  DateTime? _lockedUntil;

  Future<void> startIfEnabled(AppState app) async {
    final s = await LanSettings.load();
    if (s.enabled && s.pin.isNotEmpty) await start(app, s);
  }

  Future<void> start(AppState app, LanSettings settings) async {
    await stop();
    _app = app;
    _settings = settings;
    final ips = await _localIps();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, settings.port, shared: false);
      _server!.listen(_handle, onError: (_) {});
    } catch (e) {
      _server = null;
      status.value = LanServerStatus(error: 'Could not start on port ${settings.port}: $e');
      return;
    }
    String? secureError;
    try {
      final host = Platform.localHostname;
      _cert = await LanCert.ensure(ips: ips, hostnames: [host, '$host.local']);
      _secureServer = await HttpServer.bindSecure(InternetAddress.anyIPv4, settings.port + 1, _cert!.securityContext());
      _secureServer!.listen(_handle, onError: (_) {});
    } catch (e) {
      _secureServer = null;
      secureError = 'Secure server (port ${settings.port + 1}) failed: $e';
    }
    status.value = LanServerStatus(
      running: true,
      urls: [for (final ip in ips) 'http://$ip:${settings.port}'],
      secureUrls: _secureServer == null ? const [] : [for (final ip in ips) 'https://$ip:${settings.port + 1}'],
      error: secureError,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    await _secureServer?.close(force: true);
    _server = null;
    _secureServer = null;
    status.value = const LanServerStatus();
  }

  /// This PC's home-network IPv4 addresses, 192.168.x.x first.
  static Future<List<String>> _localIps() async {
    final ips = <String>[];
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        // Link-local (169.254.x.x) addresses belong to unplugged adapters; phones can't use them
        if (_isPrivate(a) && !a.isLinkLocal && !a.isLoopback) ips.add(a.address);
      }
    }
    ips.sort((a, b) => (b.startsWith('192.168.') ? 1 : 0) - (a.startsWith('192.168.') ? 1 : 0));
    return ips;
  }

  static bool _isPrivate(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal) return true;
    if (a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
  }

  // ─── Request handling ──────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null || !_isPrivate(remote)) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      final path = req.uri.path;

      if (path == '/' || path == '/index.html') return await _sendAsset(res, 'assets/lan/index.html', 'text/html; charset=utf-8');
      if (path == '/vr.js') return await _sendAsset(res, 'assets/lan/vr.js', 'text/javascript; charset=utf-8');
      if (path == '/setup') return await _sendAsset(res, 'assets/lan/setup.html', 'text/html; charset=utf-8');
      // The CA certificate is public by nature; the phone installs it to trust the HTTPS page
      if (path == '/ca.cer' && _cert != null) {
        res.headers
          ..set(HttpHeaders.contentTypeHeader, 'application/x-x509-ca-cert')
          ..set('Content-Disposition', 'attachment; filename="PML-Local-CA.cer"');
        res.add(_cert!.caCertDer);
        return await res.close();
      }
      if (path == '/api/login' && req.method == 'POST') return await _login(req);

      if (!_authorized(req)) {
        res.statusCode = HttpStatus.unauthorized;
        await res.close();
        return;
      }
      final app = _app;
      if (app == null || !app.isReady) {
        res.statusCode = HttpStatus.serviceUnavailable;
        await res.close();
        return;
      }

      if (path == '/api/library') return await _sendJson(res, await _library(app));
      if (path == '/api/items') return await _sendJson(res, await _items(app, req.uri.queryParameters));
      if (path.startsWith('/thumbs/')) return await _sendThumb(app, req, path.substring(8));
      if (path.startsWith('/media/')) return await _sendMedia(app, req, path.substring(7));

      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (e) {
      // Phones drop connections mid-stream all the time (seeking, closing the player)
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest req) {
    final token = _settings?.token;
    if (token == null) return false;
    // Query parameter for <video>/<img> requests, cookie for everything else
    if (req.uri.queryParameters['t'] == token) return true;
    return req.cookies.any((c) => c.name == 'pml_token' && c.value == token);
  }

  Future<void> _login(HttpRequest req) async {
    final res = req.response;
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      res.statusCode = HttpStatus.tooManyRequests;
      return res.close();
    }
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    final s = _settings!;
    if (s.pin.isEmpty || body['pin'] != s.pin) {
      _failedLogins++;
      if (_failedLogins >= 10) {
        _lockedUntil = DateTime.now().add(const Duration(minutes: 1));
        _failedLogins = 0;
      }
      await Future.delayed(const Duration(milliseconds: 600));
      res.statusCode = HttpStatus.unauthorized;
      return res.close();
    }
    _failedLogins = 0;
    res.cookies.add(Cookie('pml_token', s.token)
      ..httpOnly = true
      ..path = '/'
      ..maxAge = 60 * 60 * 24 * 365);
    await _sendJson(res, {'token': s.token});
  }

  Future<Map<String, Object?>> _library(AppState app) async {
    final st = status.value;
    return {
      // The HTTPS page has its own storage, so it gets the token from here (the cookie is shared)
      'token': _settings!.token,
      'secureUrl': st.secureUrls.isEmpty ? null : st.secureUrls.first,
      'setupUrl': st.urls.isEmpty ? null : '${st.urls.first}/setup',
      'categories': [
        for (final c in app.categoryList)
          {
            'id': c.id,
            'name': c.name,
            'subs': [for (final s in app.subcategoriesFor(c.id)) {'id': s.id, 'name': s.name}],
          },
      ],
      'tags': [for (final t in app.tagList) {'id': t.id, 'name': t.name}],
      'keys': [
        for (final k in app.tagKeyList)
          {
            'key': k.key,
            'values': [for (final v in app.valuesForKey(k.id)) {'id': v.id, 'value': v.value}],
          },
      ],
    };
  }

  /// `sub=<id>` lists a subcategory, `fav=1` favourites, `vr=1` VR videos;
  /// otherwise `tags`, `kv` (comma-separated ids) and `q` (file name) search everything.
  Future<List<Map<String, Object?>>> _items(AppState app, Map<String, String> q) async {
    List<MediaItem> list;
    if (q['sub'] case final sub? when sub.isNotEmpty) {
      list = await app.items!.listItemsInSubcategory(sub);
    } else if (q['fav'] == '1') {
      list = await app.items!.listFavourites();
    } else if (q['vr'] == '1') {
      final videos = await app.items!.listAllVideoItems();
      final vr = await app.items!.listVrFormats(videos.map((e) => e.id).toList());
      list = videos.where((v) => vr.containsKey(v.id)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      List<String> ids(String? s) => (s ?? '').split(',').where((e) => e.isNotEmpty).toList();
      list = await app.items!.searchItemsGlobal(simpleTagIds: ids(q['tags']), keyValueIds: ids(q['kv']), filename: q['q']);
    }
    // Narrow a listing by file name too
    final name = q['q']?.trim().toLowerCase() ?? '';
    if (name.isNotEmpty && (q.containsKey('sub') || q['fav'] == '1' || q['vr'] == '1')) {
      list = list.where((e) => e.originalName.toLowerCase().contains(name)).toList();
    }
    list = list.where((e) => e.type != ItemType.other).toList();

    final vr = await app.items!.listVrFormats(list.map((e) => e.id).toList());
    final thumbs = app.paths!.thumbsDir.path;
    return [
      for (final it in list)
        {
          'id': it.id,
          'name': it.originalName,
          'type': it.type == ItemType.video ? 'video' : 'image',
          'ext': p.extension(it.storedRelPath).toLowerCase(),
          'size': it.sizeBytes,
          'fav': it.isFavourite,
          'vr': vr[it.id]?.label,
          // Missing video thumbnails are generated on request
          'thumb': it.type == ItemType.video || File(p.join(thumbs, '${it.id}.jpg')).existsSync(),
        },
    ];
  }

  Future<void> _sendThumb(AppState app, HttpRequest req, String id) async {
    final f = File(p.join(app.paths!.thumbsDir.path, '${p.basename(id)}.jpg'));
    if (!await f.exists() && !await _generateThumb(app, p.basename(id))) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }
    req.response.headers
      ..contentType = ContentType('image', 'jpeg')
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=86400');
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  /// Extracts a frame 10% into the video as its thumbnail, saved in the Library's
  /// thumbs folder like the ones the app makes (so the desktop grid gets it too).
  Future<bool> _generateThumb(AppState app, String id) {
    return _thumbJobs[id] ??= () async {
      final done = Completer<bool>();
      _thumbQueue = _thumbQueue.then((_) async {
        try {
          final items = await app.items!.listItemsByIds([id]);
          if (items.isEmpty || items.first.type != ItemType.video) return done.complete(false);
          final service = ThumbnailService(app.paths!.thumbsDir);
          final video = LibraryFolders.absPath(app.paths!.filesDir, items.first.storedRelPath);
          final duration = await service.getVideoDuration(video) ?? 0;
          done.complete(await service.extractFrame(
            videoPath: video,
            timestampSeconds: duration * 0.1,
            outputPath: service.thumbnailPath(id),
            width: 480,
          ));
        } catch (_) {
          done.complete(false);
        }
      });
      final ok = await done.future;
      _thumbJobs.remove(id);
      return ok;
    }();
  }

  static const _mime = {
    '.mp4': 'video/mp4', '.m4v': 'video/mp4', '.mov': 'video/quicktime', '.webm': 'video/webm',
    '.mkv': 'video/x-matroska', '.avi': 'video/x-msvideo',
    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.gif': 'image/gif',
    '.webp': 'image/webp', '.bmp': 'image/bmp',
  };

  /// Serves a library file with HTTP range support so the phone can seek
  /// without downloading the whole thing.
  Future<void> _sendMedia(AppState app, HttpRequest req, String id) async {
    final res = req.response;
    final items = await app.items!.listItemsByIds([id]);
    if (items.isEmpty) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    final file = File(LibraryFolders.absPath(app.paths!.filesDir, items.first.storedRelPath));
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    final length = await file.length();
    res.headers
      ..set(HttpHeaders.contentTypeHeader, _mime[p.extension(file.path).toLowerCase()] ?? 'application/octet-stream')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');

    var start = 0, end = length - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null) {
      final a = range.group(1)!, b = range.group(2)!;
      if (a.isEmpty && b.isNotEmpty) {
        start = max(0, length - int.parse(b)); // suffix range: last N bytes
      } else {
        start = int.tryParse(a) ?? 0;
        if (b.isNotEmpty) end = min(int.parse(b), length - 1);
      }
      if (start > end || start >= length) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        return res.close();
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }
    res.contentLength = end - start + 1;
    if (req.method == 'HEAD') return res.close();
    await res.addStream(file.openRead(start, end + 1));
    await res.close();
  }

  Future<void> _sendJson(HttpResponse res, Object? data) async {
    res.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    res.write(jsonEncode(data));
    await res.close();
  }

  Future<void> _sendAsset(HttpResponse res, String asset, String contentType) async {
    res.headers
      ..set(HttpHeaders.contentTypeHeader, contentType)
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    res.write(await rootBundle.loadString(asset));
    await res.close();
  }
}
