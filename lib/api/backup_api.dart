// lib/api/backup_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class BackupApi {
  final AppConfig config;
  final http.Client _client;

  BackupApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> createBackup() async {
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/admin/backup'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Fehler beim Backup: ${response.statusCode}');
  }

  Future<List<String>> listBackups() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/admin/backups'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return List<String>.from(data['backups'] as List);
    }
    throw Exception('Fehler beim Laden: ${response.statusCode}');
  }
}
