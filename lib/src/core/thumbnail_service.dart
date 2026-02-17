import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// URLs for auto-downloading ffmpeg essentials builds.
/// Using gyan.dev release builds (widely trusted, official Windows builds).
const _ffmpegDownloadUrlWindows =
    'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';

/// Service for extracting video thumbnails using ffmpeg.
///
/// Ffmpeg resolution order:
/// 1. Bundled: `<exe_dir>/ffmpeg/ffmpeg.exe` (portable)
/// 2. System PATH
///
/// If neither is found, [downloadFfmpeg] can fetch it automatically.
class ThumbnailService {
  final Directory thumbsDir;

  ThumbnailService(this.thumbsDir);

  // ─── Ffmpeg location resolution ────────────

  /// Cached resolved paths (null = not yet resolved).
  static String? _resolvedFfmpeg;
  static String? _resolvedFfprobe;

  /// Directory where bundled ffmpeg lives (next to the app executable).
  static Directory get _bundledDir {
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    return Directory(p.join(exeDir.path, 'ffmpeg'));
  }

  /// Resolve the ffmpeg binary path. Checks bundled first, then PATH.
  static Future<String?> _resolveFfmpeg() async {
    if (_resolvedFfmpeg != null) return _resolvedFfmpeg;

    // 1. Check bundled location
    final bundled = _bundledDir;
    if (Platform.isWindows) {
      final exe = File(p.join(bundled.path, 'ffmpeg.exe'));
      if (await exe.exists()) {
        _resolvedFfmpeg = exe.path;
        return _resolvedFfmpeg;
      }
      // Also check one level deeper (zip often extracts as ffmpeg-N.N-essentials/bin/)
      await for (final entity in bundled.list(recursive: true)) {
        if (entity is File && p.basename(entity.path).toLowerCase() == 'ffmpeg.exe') {
          _resolvedFfmpeg = entity.path;
          return _resolvedFfmpeg;
        }
      }
    } else {
      final exe = File(p.join(bundled.path, 'ffmpeg'));
      if (await exe.exists()) {
        _resolvedFfmpeg = exe.path;
        return _resolvedFfmpeg;
      }
    }

    // 2. Check system PATH
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffmpeg'],
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) {
          _resolvedFfmpeg = 'ffmpeg'; // Just use the name, it's on PATH
          return _resolvedFfmpeg;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Resolve the ffprobe binary path.
  static Future<String?> _resolveFfprobe() async {
    if (_resolvedFfprobe != null) return _resolvedFfprobe;

    // 1. Bundled
    final bundled = _bundledDir;
    if (Platform.isWindows) {
      final exe = File(p.join(bundled.path, 'ffprobe.exe'));
      if (await exe.exists()) {
        _resolvedFfprobe = exe.path;
        return _resolvedFfprobe;
      }
      await for (final entity in bundled.list(recursive: true)) {
        if (entity is File && p.basename(entity.path).toLowerCase() == 'ffprobe.exe') {
          _resolvedFfprobe = entity.path;
          return _resolvedFfprobe;
        }
      }
    } else {
      final exe = File(p.join(bundled.path, 'ffprobe'));
      if (await exe.exists()) {
        _resolvedFfprobe = exe.path;
        return _resolvedFfprobe;
      }
    }

    // 2. System PATH
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffprobe'],
      );
      if (result.exitCode == 0) {
        _resolvedFfprobe = 'ffprobe';
        return _resolvedFfprobe;
      }
    } catch (_) {}

    return null;
  }

  /// Check if ffmpeg is available (bundled or on PATH).
  static Future<bool> isFfmpegAvailable() async {
    final ff = await _resolveFfmpeg();
    if (ff == null) return false;
    try {
      final result = await Process.run(ff, ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      // Reset cache if execution fails
      _resolvedFfmpeg = null;
      return false;
    }
  }

  // ─── Auto-download ─────────────────────────

  /// Download ffmpeg essentials and extract to the bundled directory.
  /// [onProgress] is called with a status message for UI updates.
  /// Returns true if successful.
  static Future<bool> downloadFfmpeg({
    void Function(String status)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      onProgress?.call('Auto-download is only supported on Windows.\nPlease install ffmpeg manually.');
      return false;
    }

    final bundled = _bundledDir;
    final zipPath = p.join(bundled.path, '_ffmpeg_download.zip');

    try {
      await bundled.create(recursive: true);

      // 1. Download
      onProgress?.call('Downloading ffmpeg (~90MB)...');
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Invoke-WebRequest -Uri "$_ffmpegDownloadUrlWindows" -OutFile "$zipPath" -UseBasicParsing',
      ]);
      if (result.exitCode != 0) {
        onProgress?.call('Download failed: ${result.stderr}');
        return false;
      }

      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        onProgress?.call('Download failed: file not created.');
        return false;
      }

      // 2. Extract
      onProgress?.call('Extracting...');
      final extractResult = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Path "$zipPath" -DestinationPath "${bundled.path}" -Force',
      ]);
      if (extractResult.exitCode != 0) {
        onProgress?.call('Extract failed: ${extractResult.stderr}');
        return false;
      }

      // 3. Find the bin folder and move ffmpeg.exe + ffprobe.exe to bundled root
      // The zip typically extracts as ffmpeg-N.N.N-essentials_build/bin/ffmpeg.exe
      onProgress?.call('Setting up...');
      await for (final entity in bundled.list(recursive: true)) {
        if (entity is File) {
          final name = p.basename(entity.path).toLowerCase();
          if (name == 'ffmpeg.exe' || name == 'ffprobe.exe') {
            final dest = File(p.join(bundled.path, name));
            if (entity.path != dest.path) {
              await entity.copy(dest.path);
            }
          }
        }
      }

      // 4. Verify
      final ffmpegExe = File(p.join(bundled.path, 'ffmpeg.exe'));
      final ffprobeExe = File(p.join(bundled.path, 'ffprobe.exe'));
      if (!await ffmpegExe.exists() || !await ffprobeExe.exists()) {
        onProgress?.call('Setup failed: binaries not found after extraction.');
        return false;
      }

      // 5. Clean up zip and extracted subfolder
      try { await zipFile.delete(); } catch (_) {}
      // Clean up extracted subfolder (keep only the .exe files at root)
      await for (final entity in bundled.list()) {
        if (entity is Directory) {
          try { await entity.delete(recursive: true); } catch (_) {}
        }
      }

      // 6. Reset cache so next call finds the new binaries
      _resolvedFfmpeg = null;
      _resolvedFfprobe = null;

      onProgress?.call('Done! ffmpeg is ready.');
      return true;
    } catch (e) {
      onProgress?.call('Error: $e');
      return false;
    }
  }

  // ─── Thumbnail operations ──────────────────

  /// Returns the thumbnail file for an item, or null if none exists.
  File? getThumbnail(String itemId) {
    final f = File(p.join(thumbsDir.path, '$itemId.jpg'));
    return f.existsSync() ? f : null;
  }

  /// Returns the path where a thumbnail would be stored for an item.
  String thumbnailPath(String itemId) => p.join(thumbsDir.path, '$itemId.jpg');

  /// Get video duration in seconds using ffprobe.
  Future<double?> getVideoDuration(String videoPath) async {
    final probe = await _resolveFfprobe();
    if (probe == null) return null;
    try {
      final result = await Process.run(probe, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        videoPath,
      ]);
      if (result.exitCode != 0) return null;
      return double.tryParse((result.stdout as String).trim());
    } catch (_) {
      return null;
    }
  }

  /// Extract a single frame at a given timestamp (seconds) to a destination file.
  Future<bool> extractFrame({
    required String videoPath,
    required double timestampSeconds,
    required String outputPath,
    int width = 320,
  }) async {
    final ff = await _resolveFfmpeg();
    if (ff == null) return false;
    try {
      await File(outputPath).parent.create(recursive: true);
      final result = await Process.run(ff, [
        '-y',
        '-ss', timestampSeconds.toStringAsFixed(2),
        '-i', videoPath,
        '-vframes', '1',
        '-vf', 'scale=$width:-1',
        '-q:v', '3',
        outputPath,
      ]);
      return result.exitCode == 0 && File(outputPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Extract 9 frames at random(ish) positions for the Netflix-style 3x3 picker.
  /// Returns list of temp file paths. Caller must clean up.
  Future<List<String>> extract9Frames({
    required String videoPath,
    required String tempDir,
    int width = 320,
  }) async {
    final duration = await getVideoDuration(videoPath);
    if (duration == null || duration < 1.0) return [];

    final rng = Random();
    final segmentLength = duration / 9;
    final frames = <String>[];

    for (int i = 0; i < 9; i++) {
      final segStart = segmentLength * i;
      final segEnd = segmentLength * (i + 1);
      final minT = segStart + 0.5;
      final maxT = segEnd - 0.5;
      final t = minT < maxT
          ? minT + rng.nextDouble() * (maxT - minT)
          : segStart + segmentLength / 2;

      final outPath = p.join(tempDir, 'frame_$i.jpg');
      final ok = await extractFrame(
        videoPath: videoPath,
        timestampSeconds: t.clamp(0.1, duration - 0.1),
        outputPath: outPath,
        width: width,
      );
      if (ok) frames.add(outPath);
    }

    return frames;
  }

  /// Save a chosen frame as the thumbnail for an item.
  Future<bool> setThumbnail({
    required String itemId,
    required String sourceFramePath,
  }) async {
    try {
      final dest = File(thumbnailPath(itemId));
      await dest.parent.create(recursive: true);
      await File(sourceFramePath).copy(dest.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete thumbnail for an item.
  Future<void> deleteThumbnail(String itemId) async {
    final f = File(thumbnailPath(itemId));
    if (await f.exists()) await f.delete();
  }
}
