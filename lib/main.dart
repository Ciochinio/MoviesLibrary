import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'src/app.dart';
import 'src/core/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop SQLite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // media_kit — must be called before any Player is created
  MediaKit.ensureInitialized();

  final appState = AppState();
  await appState.bootstrap();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const PortableMediaLibraryApp(),
    ),
  );
}
