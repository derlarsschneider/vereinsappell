import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config_loader.dart';
import 'headers.dart';

class MonitoringApi {
  final AppConfig config;
  final http.Client _client;

  MonitoringApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> getStats(String timeframe) async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/monitoring/stats?timeframe=$timeframe'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Fehler beim Laden der Monitoring-Daten: ${response.statusCode}');
    }
  }
}
