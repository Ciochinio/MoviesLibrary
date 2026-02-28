import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';

import 'package:google_fonts/google_fonts.dart';

import 'src/app.dart';
import 'src/core/app_state.dart';
import 'src/ui/widgets/media_player_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Disable network font fetching — fonts fall back to system sans-serif
  // instead of crashing on platforms with restricted network (macOS sandbox)
  GoogleFonts.config.allowRuntimeFetching = false;

  // Desktop SQLite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // media_kit
  MediaKit.ensureInitialized();

  // window_manager — needed for true OS fullscreen
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(800, 600),
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions);
  await windowManager.show();

  final appState = AppState();
  await appState.bootstrap();

  // Init session volume from persisted settings
  SessionVolume.instance.initFromSettings(appState.settings.startMuted);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const PortableMediaLibraryApp(),
    ),
  );
}