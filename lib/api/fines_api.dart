import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class FinesApi {
  final AppConfig config;

  FinesApi(this.config);

  Future<Map<String, dynamic>> fetchFines(String memberId) async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/fines?memberId=${memberId}'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final Map<String, dynamic> body = jsonDecode(response.body);
      final List<dynamic> fines = body['fines'];
      final String name = body['name'];
      return body;
    } else {
      throw Exception('Fehler beim Laden der Strafen: ${response.statusCode}');
    }
  }

  Future<void> addFine(String memberId, String reason, double amount) async {
    // Float types are not supported. Use Decimal types instead
    final decimalAmount = Decimal.parse(amount.toString());
    // Generate a unique ID for the fine
    final fineId = DateTime
        .now()
        .millisecondsSinceEpoch
        .toString();
    final response = await http.post(
      Uri.parse('${config.apiBaseUrl}/fines'),
      headers: headers(config),
      body: json.encode({
        'fineId': fineId,
        'memberId': memberId,
        'reason': reason,
        'amount': decimalAmount,
      }),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception('Fehler beim Speichern der Strafe: ${response.statusCode}');
    }
  }

  Future<void> deleteFine(String fineId, String memberId) async {
    final response = await http.delete(
      Uri.parse('${config.apiBaseUrl}/fines/$fineId?memberId=$memberId'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw Exception('Fehler beim Löschen der Strafe: ${response.statusCode}');
    }
  }
}