import 'package:path/path.dart' as p;

import 'app_state.dart';
import 'library_folders.dart';
import 'models.dart';
import 'thumbnail_service.dart';

/// Projection/stereo layout of a VR video, stored as the custom tag `VR: <label>`.
enum VrFormat {
  sbs180('180 SBS'),
  sbs360('360 SBS'),
  tb360('360 TB'),
  flatSbs('3D SBS');

  final String label;
  const VrFormat(this.label);

  static VrFormat? fromLabel(String? label) {
    for (final f in values) {
      if (f.label == label) return f;
    }
    return null;
  }
}

/// Custom tag key holding the VR format. Values are [VrFormat.label].
const vrTagKey = 'VR';

final _token = RegExp(r'[a-z0-9]+');

/// Guesses the VR format from the file name and video size.
/// Returns null for normal (flat) videos.
VrFormat? guessVrFormat(String fileName, {int? width, int? height}) {
  final tokens = _token.allMatches(p.basenameWithoutExtension(fileName).toLowerCase()).map((m) => m.group(0)!).toSet();
  final ratio = (width != null && height != null && height > 0) ? width / height : null;

  final saysVr = tokens.contains('vr') || tokens.contains('vr180') || tokens.contains('vr360');
  final says360 = tokens.contains('360') || tokens.contains('vr360');
  final says180 = tokens.contains('180') || tokens.contains('vr180');
  final saysTb = tokens.contains('tb') || tokens.contains('ou');
  final saysSbs = tokens.contains('sbs') || tokens.contains('lr');

  if (says360) return saysTb || (ratio != null && ratio < 1.5) ? VrFormat.tb360 : VrFormat.sbs360;
  if (says180 || saysVr) return VrFormat.sbs180;
  // 3D movies: side-by-side but not wrapped around you
  if (saysSbs) return VrFormat.flatSbs;
  // No hint in the name: VR180 SBS is 2:1 and high-res; normal videos are 16:9
  if (ratio != null && ratio > 1.95 && ratio < 2.05 && width! >= 2880) return VrFormat.sbs180;
  return null;
}

/// Reads the size of [item]'s file and tags it as VR when it looks like one.
/// Leaves items that already have a VR tag alone. Returns the format applied, if any.
Future<VrFormat?> autoTagVr(AppState app, MediaItem item) async {
  if (item.type != ItemType.video) return null;
  final existing = await app.items!.listVrFormats([item.id]);
  if (existing.containsKey(item.id)) return null;

  final path = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);
  final size = await ThumbnailService.probeVideoSize(path);
  final format = guessVrFormat(item.originalName, width: size?.width, height: size?.height);
  if (format != null) await setVrFormat(app, item.id, format);
  return format;
}

/// Sets (or with null, clears) the VR format of an item. One VR value per item.
Future<void> setVrFormat(AppState app, String itemId, VrFormat? format) async {
  final keyId = await app.tags!.getOrCreateTagKeyId(vrTagKey);
  final current = await app.items!.listKeyValuesForItem(itemId);
  for (final kv in current.where((kv) => kv.keyId == keyId)) {
    await app.items!.removeKeyValueFromItem(itemId, kv.id);
  }
  if (format != null) {
    final kvId = await app.tags!.getOrCreateKeyValueId(keyId, format.label);
    await app.items!.addKeyValueToItem(itemId, kvId);
  }
  await app.items!.writeSidecarForItemId(itemId);
}

/// Runs [autoTagVr] over every video in the library. Returns how many got tagged.
Future<int> scanLibraryForVr(AppState app, {void Function(int done, int total)? onProgress}) async {
  final videos = await app.items!.listAllVideoItems();
  var tagged = 0;
  for (var i = 0; i < videos.length; i++) {
    if (await autoTagVr(app, videos[i]) != null) tagged++;
    onProgress?.call(i + 1, videos.length);
  }
  return tagged;
}
