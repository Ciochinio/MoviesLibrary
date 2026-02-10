import 'package:flutter/material.dart';

import 'ui/shell.dart';

class PortableMediaLibraryApp extends StatelessWidget {
  const PortableMediaLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portable Media Library',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
