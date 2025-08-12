// lib/config_loader.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// Mobile/Desktop-Support
import 'package:path_provider/path_provider.dart';

import 'api/headers.dart';
import 'storage.dart';

class AppConfig {
  final String apiBaseUrl;
  final String applicationId;
  final String memberId;
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

class Member extends ChangeNotifier {
  final AppConfig config;

  String _name = '';
  bool _isSpiess = false;
  bool _isAdmin = false;
  String _token = '';

  String _street = '';
  String _houseNumber = '';
  String _postalCode = '';
  String _city = '';
  String _phone1 = '';
  String _phone2 = '';

  Member({required this.config}) {
    fetchMember();
  }

  // Getter
  String get name => _name;
  bool get isSpiess => _isSpiess;
  bool get isAdmin => _isAdmin;
  String get token => _token;

  String get street => _street;
  String get houseNumber => _houseNumber;
  String get postalCode => _postalCode;
  String get city => _city;
  String get phone1 => _phone1;
  String get phone2 => _phone2;

  // Setter
  set name(String value) => _name = value;
  set isSpiess(bool value) => _isSpiess = value;
  set isAdmin(bool value) => _isAdmin = value;
  set token(String value) => _token = value;

  set street(String value) => _street = value;
  set houseNumber(String value) => _houseNumber = value;
  set postalCode(String value) => _postalCode = value;
  set city(String value) => _city = value;
  set phone1(String value) => _phone1 = value;
  set phone2(String value) => _phone2 = value;

  Future<void> fetchMember() async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/members/${config.memberId}'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic>? member = jsonDecode(response.body);
      updateMember(member);
    } else {
      print('Fehler beim Laden des Mitglieds: ${response.statusCode}');
      print('${response.body}');
      throw Exception('Fehler beim Laden des Mitglieds: ${response.statusCode}');
    }
  }

  Future<void> saveMember() async {
    if (_name.isEmpty) {
      print('❌ Name ist leer');
      return;
    }
    print('✅ Mitgliedsdaten speichern');
    final response = await http.post(
      Uri.parse('${config.apiBaseUrl}/members'),
      headers: headers(config),
      body: encodeMember(),
    );
    if (response.statusCode == 200) {
      print('✅ Mitgliedsdaten gespeichert');
    } else {
      print('❌ Fehler beim Speichern: ${response.statusCode}');
      throw Exception('Fehler beim Speichern des Mitglieds');
    }
  }

  Future<void> registerPushSubscriptionWeb() async {
    print('Web: Registriere Push-Subscription');
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyARJfC5X_25RTZjHZQhOtFThFrrlXqH_f0",
        authDomain: "vereinsappell.firebaseapp.com",
        projectId: "vereinsappell",
        storageBucket: "vereinsappell.firebasestorage.app",
        messagingSenderId: "336568095877",
        appId: "1:336568095877:web:39669b73fb3fd869e8c5ec",
        measurementId: "G-JBREPFQ05W",
      ),
    );

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission();
    print('🔐 Berechtigungen: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Authorized. Getting token.');
      String? token = await messaging.getToken(
        vapidKey: 'BBSL8reEOfzpFNt1szHEaEyEBUCszCFTdeWL4jupUNfs5eF_Kw_uvfcIWQ10ZOPpzewMNSlYcQIcN1C3TKhKsbM',
      );
      print("📱 FCM Token: $token");
      if (token != null && token != _token) {
        _token = token;
        print('🎯 Neuer WebPush-Token: $_token');
        await saveMember();
      }
    }
  }

  void updateMember(Map<String, dynamic>? member) {
    _name = member?['name'] ?? '';
    _isSpiess = member?['isSpiess'] ?? false;
    _isAdmin = member?['isAdmin'] ?? false;
    _token = member?['token'] ?? '';

    _street = member?['street'] ?? '';
    _houseNumber = member?['houseNumber'] ?? '';
    _postalCode = member?['postalCode'] ?? '';
    _city = member?['city'] ?? '';
    _phone1 = member?['phone1'] ?? '';
    _phone2 = member?['phone2'] ?? '';

    notifyListeners();
  }

  String encodeMember() {
    return jsonEncode({
      'memberId': config.memberId,
      'name': _name,
      'isSpiess': _isSpiess,
      'isAdmin': _isAdmin,
      'token': _token,
      'street': _street,
      'houseNumber': _houseNumber,
      'postalCode': _postalCode,
      'city': _city,
      'phone1': _phone1,
      'phone2': _phone2,
    });
  }
}
