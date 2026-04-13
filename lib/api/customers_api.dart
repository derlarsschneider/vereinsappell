// lib/api/customers_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class CustomersApi {
  final AppConfig config;
  final http.Client _client;

  CustomersApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> getCustomer(String customerId) async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/customers/$customerId'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Laden des Vereins: ${response.statusCode}');
    }
  }
}
