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

// ✅ Mitglied laden
class Member extends ChangeNotifier {
  final AppConfig config;
  String _name = '';
  bool _isSpiess = false;
  bool _isAdmin = false;
  String _token = '';

  Member({required this.config}) {
    fetchMember();
  }

  String get name => _name;
  bool get isSpiess => _isSpiess;
  bool get isAdmin => _isAdmin;
  String get token => _token;

  set token(String value) {
    _token = value;
  }

  Future<void> fetchMember() async {
    // try {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/members/${config.memberId}'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic>? member = jsonDecode(response.body);
      _name = member?['name'] ?? '';
      _isSpiess = member?['isSpiess'] ?? false;
      _isAdmin = member?['isAdmin'] ?? false;
      _token = member?['token'] ?? '';
      notifyListeners();
    } else {
      print('Fehler beim Laden des Mitglieds: ${response.statusCode}');
      print('${response.body}');
      throw Exception(
        'Fehler beim Laden des Mitglieds: ${response.statusCode}',
      );
    }
    // } catch (e) {
    //   print('Fehler beim Parsen des Mitglieds: $e');
    // }
  }

  Future<void> saveMember() async {
    // try {
    if (_name.isEmpty) {
      print('❌ Name ist leer');
      return;
    }
    print('✅ Mitgliedsdaten speichern');
    final response = await http.post(
      Uri.parse('${config.apiBaseUrl}/members'),
      headers: headers(config),
      body: jsonEncode({
        'memberId': config.memberId,
        'name': _name,
        'isSpiess': _isSpiess,
        'isAdmin': _isAdmin,
        'token': _token,
      }),
    );
    print('✅ Mitgliedsdaten gespeichert');

    if (response.statusCode == 200) {
      print('✅ Mitgliedsdaten gespeichert');
    } else {
      print('❌ Fehler beim Speichern: ${response.statusCode}');
      throw Exception('Fehler beim Speichern des Mitglieds');
    }
    // } catch (e) {
    //   print('❌ Ausnahme beim Speichern: $e');
    // }
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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
        await saveMember(); // Token im Backend speichern
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('${message.notification?.title}: ${message.notification?.body}');
    });
  }

  Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    print('🔙 Hintergrundnachricht: ${message.messageId}');
  }
}
