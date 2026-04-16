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

  Future<List<Map<String, dynamic>>> listCustomers() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/customers'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Fehler beim Laden der Vereine: ${response.statusCode}');
    }
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    final response = await _client.put(
      Uri.parse('${config.apiBaseUrl}/customers/$id'),
      headers: headers(config),
      body: json.encode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Speichern: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/customers'),
      headers: headers(config),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Erstellen: ${response.statusCode}');
    }
  }
}
