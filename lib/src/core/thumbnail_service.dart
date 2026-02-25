import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// URLs for auto-downloading ffmpeg essentials builds.
const _ffmpegDownloadUrlWindows =
    'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
const _ffmpegDownloadUrlMacOS =
    'https://evermeet.cx/ffmpeg/getrelease/zip';
const _ffprobeDownloadUrlMacOS =
    'https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip';

/// Service for extracting video thumbnails using ffmpeg.
///
/// Ffmpeg resolution order:
/// 1. Bundled: `<exe_dir>/ffmpeg/ffmpeg[.exe]` (portable)
/// 2. System PATH
///
/// If neither is found, [downloadFfmpeg] can fetch it automatically.
class ThumbnailService {
  final Directory thumbsDir;

  ThumbnailService(this.thumbsDir);

  // ─── Ffmpeg location resolution ────────────

  static String? _resolvedFfmpeg;
  static String? _resolvedFfprobe;

  /// Directory where bundled ffmpeg lives (next to the app executable).
  static Directory get _bundledDir {
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    return Directory(p.join(exeDir.path, 'ffmpeg'));
  }

  /// Public accessor for the bundled ffmpeg directory path (for settings UI).
  static String get bundledDirPath => _bundledDir.path;

  /// Get the currently resolved ffmpeg path (for settings UI).
  static Future<String?> resolvedFfmpegPath() async {
    return await _resolveFfmpeg();
  }

  /// Safely list a directory recursively, returning empty if it doesn't exist.
  static Future<List<FileSystemEntity>> _safeListRecursive(Directory dir) async {
    if (!await dir.exists()) return [];
    final result = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: true)) {
      result.add(entity);
    }
    return result;
  }

  /// Resolve the ffmpeg binary path. Checks bundled first, then PATH.
  static Future<String?> _resolveFfmpeg() async {
    if (_resolvedFfmpeg != null) {
      // Verify cached path still works
      try {
        final f = File(_resolvedFfmpeg!);
        if (_resolvedFfmpeg != 'ffmpeg' && !await f.exists()) {
          _resolvedFfmpeg = null;
        }
      } catch (_) {
        _resolvedFfmpeg = null;
      }
      if (_resolvedFfmpeg != null) return _resolvedFfmpeg;
    }

    final exeName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

    // 1. Check bundled location — direct path first
    final bundled = _bundledDir;
    final directExe = File(p.join(bundled.path, exeName));
    if (await directExe.exists()) {
      _resolvedFfmpeg = directExe.path;
      return _resolvedFfmpeg;
    }

    // Check one level deeper (zip often extracts as a subfolder)
    if (await bundled.exists()) {
      final entities = await _safeListRecursive(bundled);
      for (final entity in entities) {
        if (entity is File && p.basename(entity.path).toLowerCase() == exeName.toLowerCase()) {
          _resolvedFfmpeg = entity.path;
          return _resolvedFfmpeg;
        }
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
          _resolvedFfmpeg = 'ffmpeg';
          return _resolvedFfmpeg;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Resolve the ffprobe binary path.
  static Future<String?> _resolveFfprobe() async {
    if (_resolvedFfprobe != null) {
      try {
        final f = File(_resolvedFfprobe!);
        if (_resolvedFfprobe != 'ffprobe' && !await f.exists()) {
          _resolvedFfprobe = null;
        }
      } catch (_) {
        _resolvedFfprobe = null;
      }
      if (_resolvedFfprobe != null) return _resolvedFfprobe;
    }

    final exeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';

    // 1. Bundled — direct path
    final bundled = _bundledDir;
    final directExe = File(p.join(bundled.path, exeName));
    if (await directExe.exists()) {
      _resolvedFfprobe = directExe.path;
      return _resolvedFfprobe;
    }

    // Check deeper
    if (await bundled.exists()) {
      final entities = await _safeListRecursive(bundled);
      for (final entity in entities) {
        if (entity is File && p.basename(entity.path).toLowerCase() == exeName.toLowerCase()) {
          _resolvedFfprobe = entity.path;
          return _resolvedFfprobe;
        }
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
      _resolvedFfmpeg = null;
      return false;
    }
  }

  /// Returns true if auto-download is supported on this platform.
  static bool get isAutoDownloadSupported =>
      Platform.isWindows || Platform.isMacOS;

  // ─── Auto-download ─────────────────────────

  /// Download ffmpeg and extract to the bundled directory.
  /// [onProgress] is called with a status message for UI updates.
  /// Returns true if successful.
  static Future<bool> downloadFfmpeg({
    void Function(String status)? onProgress,
  }) async {
    if (Platform.isWindows) {
      return _downloadFfmpegWindows(onProgress: onProgress);
    } else if (Platform.isMacOS) {
      return _downloadFfmpegMacOS(onProgress: onProgress);
    } else {
      onProgress?.call('Auto-download is not supported on this platform.\nPlease install ffmpeg manually (e.g. sudo apt install ffmpeg).');
      return false;
    }
  }

  static Future<bool> _downloadFfmpegWindows({
    void Function(String status)? onProgress,
  }) async {
    final bundled = _bundledDir;
    final zipPath = p.join(bundled.path, '_ffmpeg_download.zip');

    try {
      await bundled.create(recursive: true);

      // 1. Download
      onProgress?.call('Downloading ffmpeg (~90MB)...\nThis may take a few minutes.');
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Invoke-WebRequest -Uri "$_ffmpegDownloadUrlWindows" -OutFile "$zipPath" -UseBasicParsing',
      ]);
      if (result.exitCode != 0) {
        onProgress?.call('Download failed: ${result.stderr}');
        return false;
      }

      if (!File(zipPath).existsSync()) {
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

      // 3. Find ffmpeg.exe and ffprobe.exe and copy to bundled root
      onProgress?.call('Setting up...');
      final entities = await _safeListRecursive(bundled);
      for (final entity in entities) {
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
      if (!File(p.join(bundled.path, 'ffmpeg.exe')).existsSync() ||
          !File(p.join(bundled.path, 'ffprobe.exe')).existsSync()) {
        onProgress?.call('Setup failed: binaries not found after extraction.');
        return false;
      }

      // 5. Clean up
      try { await File(zipPath).delete(); } catch (_) {}
      final dirEntities = await _safeListRecursive(bundled);
      // Remove extracted subfolders (keep only .exe at root)
      for (final entity in await bundled.list().toList()) {
        if (entity is Directory) {
          try { await entity.delete(recursive: true); } catch (_) {}
        }
      }

      _resolvedFfmpeg = null;
      _resolvedFfprobe = null;

      onProgress?.call('Done! ffmpeg is ready.');
      return true;
    } catch (e) {
      onProgress?.call('Error: $e');
      return false;
    }
  }

  static Future<bool> _downloadFfmpegMacOS({
    void Function(String status)? onProgress,
  }) async {
    final bundled = _bundledDir;

    try {
      await bundled.create(recursive: true);

      // 1. Download ffmpeg
      onProgress?.call('Downloading ffmpeg...');
      final ffmpegZip = p.join(bundled.path, '_ffmpeg.zip');
      var result = await Process.run('curl', [
        '-L', '-o', ffmpegZip, _ffmpegDownloadUrlMacOS,
      ]);
      if (result.exitCode != 0) {
        onProgress?.call('Download failed: ${result.stderr}');
        return false;
      }

      // 2. Download ffprobe
      onProgress?.call('Downloading ffprobe...');
      final ffprobeZip = p.join(bundled.path, '_ffprobe.zip');
      result = await Process.run('curl', [
        '-L', '-o', ffprobeZip, _ffprobeDownloadUrlMacOS,
      ]);
      if (result.exitCode != 0) {
        onProgress?.call('ffprobe download failed: ${result.stderr}');
        return false;
      }

      // 3. Extract
      onProgress?.call('Extracting...');
      result = await Process.run('unzip', ['-o', ffmpegZip, '-d', bundled.path]);
      if (result.exitCode != 0) {
        onProgress?.call('Extract failed: ${result.stderr}');
        return false;
      }
      result = await Process.run('unzip', ['-o', ffprobeZip, '-d', bundled.path]);
      if (result.exitCode != 0) {
        onProgress?.call('Extract ffprobe failed: ${result.stderr}');
        return false;
      }

      // 4. Make executable
      final ffmpegBin = File(p.join(bundled.path, 'ffmpeg'));
      final ffprobeBin = File(p.join(bundled.path, 'ffprobe'));
      if (await ffmpegBin.exists()) {
        await Process.run('chmod', ['+x', ffmpegBin.path]);
      }
      if (await ffprobeBin.exists()) {
        await Process.run('chmod', ['+x', ffprobeBin.path]);
      }

      // 5. Verify
      if (!await ffmpegBin.exists()) {
        onProgress?.call('Setup failed: ffmpeg binary not found.');
        return false;
      }

      // 6. Clean up zips
      try { await File(ffmpegZip).delete(); } catch (_) {}
      try { await File(ffprobeZip).delete(); } catch (_) {}

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

  /// Extract 9 frames at random(ish) time positions for the 3x3 picker.
  /// Returns full frames — no cropping. Caller must clean up temp files.
  Future<List<({String path, String? cropFilter})>> extract9Frames({
    required String videoPath,
    required String tempDir,
    int outputWidth = 320,
  }) async {
    final duration = await getVideoDuration(videoPath);
    if (duration == null || duration < 1.0) return [];

    final rng = Random();
    final segmentLength = duration / 9;
    final frames = <({String path, String? cropFilter})>[];

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
        width: outputWidth,
      );
      if (ok) frames.add((path: outPath, cropFilter: null));
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
