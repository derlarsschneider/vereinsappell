// lib/main.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:vereins_app_beta/screens/calendar_screen.dart';
import 'package:vereins_app_beta/screens/config_missing_screen.dart';
import 'package:vereins_app_beta/screens/default_screen.dart';
import 'package:vereins_app_beta/screens/home_screen.dart';
// import 'firebase_push_setup.dart';
// import 'screens/termine_screen.dart';
import 'config_loader.dart';
import 'screens/strafen_screen.dart';
import 'screens/spiess_screen.dart';
import 'screens/galerie_screen.dart';
// import 'screens/knobeln_screen.dart';

// final String apiBaseUrl = 'http://localhost:5000';
final String apiBaseUrl = 'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com';
final String applicationId = '';
final bool isAdmin = true;
final String appName = 'Schützenlust-Korps Neuss-Gnadental gegr. 1998';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await loadConfigFile();

  runApp(MaterialApp(
    home: config == null
        ? ConfigMissingScreen()
        : MainApp(config: config),
  ));
}

class MainApp extends StatelessWidget {
  final AppConfig config;
  const MainApp({required this.config});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainMenu(config: config),
    );
  }
}

