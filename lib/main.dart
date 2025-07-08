// lib/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vereins_app_beta/screens/config_missing_screen.dart';
import 'package:vereins_app_beta/screens/home_screen.dart';
import 'package:window_size/window_size.dart';

import 'config_loader.dart';

// // final String apiBaseUrl = 'http://localhost:5000';
// final String apiBaseUrl = 'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com';
// final String applicationId = 'lknfar-lkjfd';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('Schützenlust App');
    setWindowMinSize(const Size(400, 800));
    setWindowMaxSize(const Size(400, 800));
  }

  final config = await loadConfigFile();

  runApp(
    config == null
        ? MaterialApp(home: ConfigMissingScreen())
        : MainApp(config: config),
  );
}

class MainApp extends StatelessWidget {
  final AppConfig config;
  const MainApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Member>.value(
      value: config.member,
      child: MaterialApp(
        title: config.appName,
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: MainMenu(config: config),
      ),
    );
  }
}
