// lib/config_loader.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  final String apiBaseUrl;
  final String applicationId;
  final String memberId;
  final bool isAdmin;
  final String appName;

  AppConfig({
    required this.apiBaseUrl,
    required this.applicationId,
    required this.memberId,
    required this.isAdmin,
    required this.appName,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      apiBaseUrl: json['apiBaseUrl'],
      applicationId: json['applicationId'],
      memberId: json['memberId'],
      isAdmin: json['isAdmin'],
      appName: json['appName'],
    );
  }
}

Future<AppConfig?> loadConfigFile() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/config.json');

    if (!await file.exists()) {
      return null;
    }

    final contents = await file.readAsString();
    final jsonData = jsonDecode(contents);
    return AppConfig.fromJson(jsonData);
  } catch (e) {
    print("Fehler beim Laden der config.json: $e");
    return null;
  }
}
