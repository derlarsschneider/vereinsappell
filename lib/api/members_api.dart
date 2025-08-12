// lib/api/members_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class MembersApi {
  final AppConfig config;

  MembersApi(this.config);


  Future<List<dynamic>> fetchMembers() async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/members'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Laden der Mitglieder: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> createMember(String name, String applicationId) async {
    final memberId = '$applicationId${DateTime.now().millisecondsSinceEpoch}';
    final newMember = {
      'name': name,
      'memberId': memberId,
      'isAdmin': false,
      'isSpiess': false,
      'street': '',
      'houseNumber': '',
      'postalCode': '',
      'city': '',
      'phone1': '',
      'phone2': '',
    };
    final response = await http.post(
      Uri.parse('${config.apiBaseUrl}/members'),
      headers: headers(config),
      body: json.encode(newMember),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Erstellen: ${response.statusCode}');
    }
  }

  Future<void> saveMember(Map<String, dynamic> member) async {
    final response = await http.post(
      Uri.parse('${config.apiBaseUrl}/members'),
      headers: headers(config),
      body: json.encode(member),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Fehler beim Speichern: ${response.body}');
    }
  }

  Future<void> deleteMember(String memberId) async {
    final response = await http.delete(
      Uri.parse('${config.apiBaseUrl}/members/$memberId'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
