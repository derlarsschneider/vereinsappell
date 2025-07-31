import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:icalendar_parser/icalendar_parser.dart';

import '../config_loader.dart';
import 'headers.dart';

class CalendarApi {
  final AppConfig config;

  CalendarApi(this.config);

  Future<ICalendar> fetchIcs () async {
    final url = Uri.parse(
        'https://www.schuetzenlust-gnadental.de/index.php/termine/eventslist/?format=raw&layout=ics');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final rawIcs = response.body;
      final calendar = ICalendar.fromString(rawIcs);
      return calendar;
    } else {
      throw Exception('Fehler beim Laden des Kalenders: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getCalendar() async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/calendar'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      print('Fehler beim Laden des Kalenders: ${response.body}');
      throw Exception('Fehler beim Laden des Kalenders: ${response.statusCode}');
    }
  }

}
