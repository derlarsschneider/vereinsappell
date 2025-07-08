// lib/config_loader.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:vereins_app_beta/main.dart';

class AppConfig {
  final String apiBaseUrl;
  final String applicationId;
  final String memberId;
  final String appName = 'Schützenlust-Korps Neuss-Gnadental gegr. 1998';
  late final Member member;

  AppConfig({
    required this.apiBaseUrl,
    required this.applicationId,
    required this.memberId,
  }) {
    member = Member(config: this);
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      apiBaseUrl: json['apiBaseUrl'],
      applicationId: json['applicationId'],
      memberId: json['memberId'],
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

class Member extends ChangeNotifier {
  final AppConfig config;
  String name = '';
  bool _isSpiess = false;
  bool _isAdmin = false;

  Member({required this.config}) {
    fetchMember();
  }

  bool get isSpiess => _isSpiess;
  bool get isAdmin => _isAdmin;

  Future<void> fetchMember() async {
    try {
      final response = await http.get(Uri.parse('${config.apiBaseUrl}/members/${config.memberId}'));
      if (response.statusCode == 200) {
        final Map<String, dynamic>? member = jsonDecode(response.body);
        name = member?['name'] ?? '';
        final bool newIsSpiess = member?['isSpiess'] ?? false;
        final bool newIsAdmin = member?['isAdmin'] ?? false;

        bool changed = false;

        if (newIsSpiess != _isSpiess) {
          _isSpiess = newIsSpiess;
          changed = true;
        }

        if (newIsAdmin != _isAdmin) {
          _isAdmin = newIsAdmin;
          changed = true;
        }

        if (changed) {
          notifyListeners(); // UI benachrichtigen
        }
      } else {
        print('Fehler beim Laden des Mitglieds im Config Loader: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Parsen des Mitglieds im Config Loader: $e');
    }
  }
}
