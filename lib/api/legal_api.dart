// lib/api/legal_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class LegalApi {
  final AppConfig config;
  final http.Client _client;

  LegalApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, String>> getLegal() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/legal'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return {
        'datenschutz': body['datenschutz'] as String? ?? '',
        'impressum': body['impressum'] as String? ?? '',
      };
    }
    throw Exception('Fehler beim Laden der Rechtstexte: ${response.statusCode}');
  }

  Future<void> putLegal({
    required String datenschutz,
    required String impressum,
  }) async {
    final response = await _client.put(
      Uri.parse('${config.apiBaseUrl}/legal'),
      headers: headers(config),
      body: json.encode({'datenschutz': datenschutz, 'impressum': impressum}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Speichern: ${response.statusCode}');
    }
  }
}
