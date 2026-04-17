// lib/config_loader.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api/headers.dart';
import 'storage.dart';

class AppConfig {
  final String apiBaseUrl;
  final String applicationId;
  final String memberId;
  final String label;
  late final Member member;
  String? sessionPassword;

  AppConfig({
    required this.apiBaseUrl,
    required this.applicationId,
    required this.memberId,
    this.label = '',
    this.sessionPassword,
  }) {
    member = Member(config: this);
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      apiBaseUrl: json['apiBaseUrl'] as String,
      applicationId: json['applicationId'] as String,
      memberId: json['memberId'] as String,
      label: (json['label'] as String?) ?? '',
      sessionPassword: json['password'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'applicationId': applicationId,
      'memberId': memberId,
      'label': label,
      if (sessionPassword != null) 'password': sessionPassword,
    };
  }
}

/// Pure helper — finds the index of an account in a raw JSON list by
/// applicationId + memberId. Exported so it can be unit-tested without storage.
int accountIndexOf(
  List<Map<String, dynamic>> accounts,
  String applicationId,
  String memberId,
) {
  return accounts.indexWhere(
    (a) => a['applicationId'] == applicationId && a['memberId'] == memberId,
  );
}

// ── Storage helpers ──────────────────────────────────────────────────────────

List<Map<String, dynamic>> _readAccountsJson() {
  final raw = getItem('accounts');
  if (raw == null) return [];
  try {
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

void _writeAccountsJson(List<Map<String, dynamic>> accounts) {
  setItem('accounts', jsonEncode(accounts));
}

// ── Public API ───────────────────────────────────────────────────────────────

Future<AppConfig?> loadConfig() async {
  try {
    if (kIsWeb) {
      // Migration: move old single 'config' key → accounts array
      final oldJson = getItem('config');
      if (oldJson != null && getItem('accounts') == null) {
        final old = AppConfig.fromJson(jsonDecode(oldJson) as Map<String, dynamic>);
        _writeAccountsJson([old.toJson()]);
        setItem('activeAccount', '0');
        removeItem('config');
      }

      final accounts = _readAccountsJson();
      if (accounts.isEmpty) return null;
      final idx = (int.tryParse(getItem('activeAccount') ?? '0') ?? 0)
          .clamp(0, accounts.length - 1);
      return AppConfig.fromJson(accounts[idx]);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (!await file.exists()) return null;
      return AppConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    }
  } catch (e) {
    print('Fehler beim Laden der Konfiguration: $e');
    return null;
  }
}

Future<void> saveConfig(AppConfig config) async {
  try {
    if (kIsWeb) {
      final accounts = _readAccountsJson();
      final idx = (int.tryParse(getItem('activeAccount') ?? '0') ?? 0)
          .clamp(0, accounts.isEmpty ? 0 : accounts.length - 1);
      if (idx < accounts.length) {
        accounts[idx] = config.toJson();
        setItem('activeAccount', '$idx');
      } else {
        accounts.add(config.toJson());
        setItem('activeAccount', '${accounts.length - 1}');
      }
      _writeAccountsJson(accounts);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      await file.writeAsString(jsonEncode(config.toJson()));
    }
  } catch (e) {
    print('Fehler beim Speichern der Konfiguration: $e');
    rethrow;
  }
}

Future<void> deleteConfig() async {
  try {
    if (kIsWeb) {
      removeItem('accounts');
      removeItem('activeAccount');
      removeItem('config');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/config.json');
      if (await file.exists()) await file.delete();
    }
  } catch (e) {
    print('Fehler beim Löschen der Konfiguration: $e');
  }
}

List<AppConfig> loadAllAccounts() {
  if (!kIsWeb) return [];
  return _readAccountsJson()
      .map((json) => AppConfig.fromJson(json))
      .toList();
}

int getActiveAccountIndex() {
  if (!kIsWeb) return 0;
  final accounts = _readAccountsJson();
  final idx = int.tryParse(getItem('activeAccount') ?? '0') ?? 0;
  return accounts.isEmpty ? 0 : idx.clamp(0, accounts.length - 1);
}

void setActiveAccount(int index) {
  if (!kIsWeb) return;
  setItem('activeAccount', '$index');
}

void removeAccount(int index) {
  if (!kIsWeb) return;
  final accounts = _readAccountsJson();
  if (index >= 0 && index < accounts.length) {
    accounts.removeAt(index);
    _writeAccountsJson(accounts);

    final currentIdx = getActiveAccountIndex();
    if (currentIdx == index) {
      // If we deleted the active account, reset to first or clear
      setActiveAccount(0);
    } else if (currentIdx > index) {
      // Shift active index down if we deleted something before it
      setActiveAccount(currentIdx - 1);
    }
  }
}

Future<void> addOrActivateAccount(AppConfig config) async {
  if (!kIsWeb) {
    await saveConfig(config);
    return;
  }
  final accounts = _readAccountsJson();
  final existing = accountIndexOf(accounts, config.applicationId, config.memberId);
  if (existing != -1) {
    final stored = accounts[existing];
    final updated = config.toJson();
    // Preserve label from stored account if the incoming one is blank.
    if ((updated['label'] as String? ?? '').isEmpty && (stored['label'] as String? ?? '').isNotEmpty) {
      updated['label'] = stored['label'];
    }
    accounts[existing] = updated;
    _writeAccountsJson(accounts);
    setActiveAccount(existing);
  } else {
    accounts.add(config.toJson());
    _writeAccountsJson(accounts);
    setActiveAccount(accounts.length - 1);
  }
}

void updateActiveAccountLabel(String label) {
  // Empty label is never stored — the club name fetch is the only source,
  // and an empty name means the fetch hasn't completed yet.
  if (!kIsWeb || label.isEmpty) return;
  final accounts = _readAccountsJson();
  final idx = getActiveAccountIndex().clamp(0, accounts.isEmpty ? 0 : accounts.length - 1);
  if (idx < accounts.length) {
    accounts[idx]['label'] = label;
    _writeAccountsJson(accounts);
  }
}

class Member extends ChangeNotifier {
  final AppConfig config;

  String _name = '';
  bool _isSpiess = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _isActive = true;
  String _token = '';

  String _street = '';
  String _houseNumber = '';
  String _postalCode = '';
  String _city = '';
  String _phone1 = '';
  String _phone2 = '';

  bool _reminderEnabled = true;
  int _reminderHoursBefore = 24;

  Member({required this.config}) {
    fetchMember();
  }

  // Getter
  String get name => _name;
  bool get isSpiess => _isSpiess;
  bool get isAdmin => _isAdmin;
  bool get isSuperAdmin => _isSuperAdmin;
  bool get isActive => _isActive;
  String get token => _token;

  String get street => _street;
  String get houseNumber => _houseNumber;
  String get postalCode => _postalCode;
  String get city => _city;
  String get phone1 => _phone1;
  String get phone2 => _phone2;

  bool get reminderEnabled => _reminderEnabled;
  int get reminderHoursBefore => _reminderHoursBefore;

  // Setter
  set name(String value) => _name = value;
  set isSpiess(bool value) => _isSpiess = value;
  set isAdmin(bool value) => _isAdmin = value;
  set isSuperAdmin(bool value) => _isSuperAdmin = value;
  set isActive(bool value) => _isActive = value;
  set token(String value) => _token = value;

  set street(String value) => _street = value;
  set houseNumber(String value) => _houseNumber = value;
  set postalCode(String value) => _postalCode = value;
  set city(String value) => _city = value;
  set phone1(String value) => _phone1 = value;
  set phone2(String value) => _phone2 = value;

  set reminderEnabled(bool v) => _reminderEnabled = v;
  set reminderHoursBefore(int v) => _reminderHoursBefore = v;

  Future<void> fetchMember() async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${config.apiBaseUrl}/members/${config.memberId}'),
        headers: headers(config),
      );
    } catch (e) {
      throw Exception('Netzwerkfehler: $e');
    }

    if (response.statusCode != 200) {
      final preview = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
      throw Exception('HTTP ${response.statusCode}: $preview');
    }

    try {
      final Map<String, dynamic>? member = jsonDecode(response.body);
      updateMember(member);
    } catch (e) {
      final preview = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
      throw Exception('Ungültige API-Antwort (kein JSON): "$preview"');
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
    _isSuperAdmin = member?['isSuperAdmin'] ?? false;
    _isActive = member?['isActive'] ?? true;
    _token = member?['token'] ?? '';

    _street = member?['street'] ?? '';
    _houseNumber = member?['houseNumber'] ?? '';
    _postalCode = member?['postalCode'] ?? '';
    _city = member?['city'] ?? '';
    _phone1 = member?['phone1'] ?? '';
    _phone2 = member?['phone2'] ?? '';

    _reminderEnabled = member?['reminderEnabled'] ?? true;
    _reminderHoursBefore = member?['reminderHoursBefore'] ?? 24;

    notifyListeners();
  }

  String encodeMember() {
    return jsonEncode({
      'memberId': config.memberId,
      'name': _name,
      'isSpiess': _isSpiess,
      'isAdmin': _isAdmin,
      'isSuperAdmin': _isSuperAdmin,
      'token': _token,
      'street': _street,
      'houseNumber': _houseNumber,
      'postalCode': _postalCode,
      'city': _city,
      'phone1': _phone1,
      'phone2': _phone2,
      'reminderEnabled': _reminderEnabled,
      'reminderHoursBefore': _reminderHoursBefore,
    });
  }
}
