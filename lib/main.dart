// lib/main.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vereinsappell/screens/config_missing_screen.dart';
import 'package:vereinsappell/screens/home_screen.dart';
import 'package:window_size/window_size.dart';

import 'config_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Platform.isLinux || Platform.isMacOS) {
      setWindowTitle('Vereins Appell');
      setWindowMinSize(const Size(400, 800));
      setWindowMaxSize(const Size(400, 800));
    }
  } catch (e) {
    print(e);
  }

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red,
      child: Center(
        child: Text(
          details.exceptionAsString(),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  };

  AppConfig? config = await loadConfig();

  if (kIsWeb) {
    final url = Uri.base;
    String? apiBaseUrlGetParam = url.queryParameters['apiBaseUrl'];
    String? applicationIdGetParam = url.queryParameters['applicationId'];
    String? memberIdGetParam = url.queryParameters['memberId'];
    String? applicationNameGetParam = url.queryParameters['applicationName'];

    String? apiBaseUrlConfigParam = config?.apiBaseUrl;
    String? applicationIdConfigParam = config?.applicationId;
    String? memberIdConfigParam = config?.memberId;
    String? applicationNameConfigParam = config?.memberId;

    String? apiBaseUrl = apiBaseUrlGetParam ?? apiBaseUrlConfigParam;
    String? applicationId = applicationIdGetParam ?? applicationIdConfigParam;
    String? memberId = memberIdGetParam ?? memberIdConfigParam;
    String? applicationName = applicationNameGetParam ?? applicationNameConfigParam;

    if (apiBaseUrl != null && applicationId != null && memberId != null && applicationName != null) {
      config = AppConfig(
        apiBaseUrl: apiBaseUrl,
        applicationId: applicationId,
        memberId: memberId,
        applicationName: applicationName,
      );
      saveConfig(config);
    }
  }

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
        title: config.applicationName,
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: HomeScreen(config: config),
      ),
    );
  }
}
