// lib/config_loader.dart
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api/headers.dart';
import 'storage.dart';

// Mobile/Desktop-Support
import 'package:path_provider/path_provider.dart';

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

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'applicationId': applicationId,
      'memberId': memberId,
    };
  }
}

// ✅ Konfiguration laden
Future<AppConfig?> loadConfig() async {
  try {
    if (kIsWeb) {
      final jsonStr = getItem('config');
      if (jsonStr == null) return null;
      final jsonData = jsonDecode(jsonStr);
      return AppConfig.fromJson(jsonData);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final jsonData = jsonDecode(contents);
      return AppConfig.fromJson(jsonData);
    }
  } catch (e) {
    print('Fehler beim Laden der Konfiguration: $e');
    return null;
  }
}

// ✅ Konfiguration speichern
Future<void> saveConfig(AppConfig config) async {
  final jsonStr = jsonEncode(config.toJson());
  try {
    if (kIsWeb) {
      setItem('config', jsonStr);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      await file.writeAsString(jsonStr);
    }
  } catch (e) {
    print('Fehler beim Speichern der Konfiguration: $e');
    rethrow;
  }
}

// ✅ Konfiguration löschen
Future<void> deleteConfig() async {
  try {
    if (kIsWeb) {
      removeItem('config');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (await file.exists()) {
        await file.delete();
      }
    }
  } catch (e) {
    print('Fehler beim Löschen der Konfiguration: $e');
  }
}

// ✅ Mitglied laden
class Member extends ChangeNotifier {
  final AppConfig config;
  String _name = '';
  bool _isSpiess = false;
  bool _isAdmin = false;

  Member({required this.config}) {
    fetchMember();
  }

  String get name => _name;
  bool get isSpiess => _isSpiess;
  bool get isAdmin => _isAdmin;

  Future<void> fetchMember() async {
    // try {
      final response = await http.get(
        Uri.parse('${config.apiBaseUrl}/members/${config.memberId}'),
        headers: headers(config),
      );
      print('${config.apiBaseUrl}/members/${config.memberId}');
      if (response.statusCode == 200) {
        final Map<String, dynamic>? member = jsonDecode(response.body);
        _name = member?['name'] ?? '';
        _isSpiess = member?['isSpiess'] ?? false;
        _isAdmin = member?['isAdmin'] ?? false;
        notifyListeners();
      } else {
        print('Fehler beim Laden des Mitglieds: ${response.statusCode}');
        throw Exception('Fehler beim Laden des Mitglieds: ${response.statusCode}');
      }
    // } catch (e) {
    //   print('Fehler beim Parsen des Mitglieds: $e');
    // }
  }
}
