import 'package:flutter_test/flutter_test.dart';
import 'package:portable_media_library/src/core/vr_format.dart';

void main() {
  test('file name hints', () {
    expect(guessVrFormat('Scene_VR180_LR.mp4'), VrFormat.sbs180);
    expect(guessVrFormat('scene 180 sbs 4k.mp4'), VrFormat.sbs180);
    expect(guessVrFormat('scene-vr.mp4'), VrFormat.sbs180);
    expect(guessVrFormat('tour_360_tb.mp4'), VrFormat.tb360);
    expect(guessVrFormat('tour 360.mp4', width: 3840, height: 1920), VrFormat.sbs360);
    expect(guessVrFormat('tour 360.mp4', width: 4096, height: 4096), VrFormat.tb360);
    expect(guessVrFormat('Movie.3D.SBS.mkv'), VrFormat.flatSbs);
  });

  test('video size without hints', () {
    expect(guessVrFormat('abc.mp4', width: 5760, height: 2880), VrFormat.sbs180);
    expect(guessVrFormat('abc.mp4', width: 3840, height: 2160), isNull);
    // 2:1 but too small to be VR (phone/cinema crops)
    expect(guessVrFormat('abc.mp4', width: 1920, height: 960), isNull);
  });

  test('does not match words that merely contain the hints', () {
    expect(guessVrFormat('overtime_1800.mp4'), isNull);
    expect(guessVrFormat('Lovers.mp4'), isNull);
  });
}
