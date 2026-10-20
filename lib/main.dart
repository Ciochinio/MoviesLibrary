import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/core/app_state.dart';
import 'src/core/lan_server.dart';
import 'src/core/session_volume.dart';
import 'src/ui/widgets/media_player_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    minimumSize: Size(1366, 768),
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions);
  await windowManager.show();

  final appState = AppState();
  await appState.bootstrap();

  // Init session volume from persisted settings
  SessionVolume.instance.initFromSettings(appState.settings.startMuted);

  // Phone access, if it was left switched on
  LanServer.instance.startIfEnabled(appState);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const PortableMediaLibraryApp(),
    ),
  );
}