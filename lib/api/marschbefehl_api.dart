import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class MarschbefehlApi {
  final AppConfig config;

  MarschbefehlApi(this.config);

  Future<List> fetchMarschbefehl() async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/marschbefehl'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Fehler beim Laden des Marschbefehls: ${response.statusCode}');
    }
  }
}
