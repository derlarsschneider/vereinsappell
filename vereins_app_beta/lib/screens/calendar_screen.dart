import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(MaterialApp(home: CalendarScreen()));
}

class CalendarScreen extends StatefulWidget {
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Map<String, dynamic>> events = [];
  bool isLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchIcs();
  }

  Future<void> fetchIcs() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // Beispiel ICS URL (kann beliebig geändert werden)
      final url = Uri.parse('https://www.schuetzenlust-gnadental.de/index.php/termine/eventslist/?format=raw&layout=ics');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final rawIcs = response.body;
        final calendar = ICalendar.fromString(rawIcs);

        setState(() {
          events = calendar.data;
        });
      } else {
        setState(() {
          error = 'Fehler beim Laden der ICS Datei: HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Fehler: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatDate(String? dt) {
    if (dt == null) return '';
    // Einfaches Formatieren von z.B. 20230704T000000Z in lesbares Datum
    if (dt.length >= 8) {
      final y = dt.substring(0, 4);
      final m = dt.substring(4, 6);
      final d = dt.substring(6, 8);
      return '$d.$m.$y';
    }
    return dt;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('📅 Termine')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : ListView.builder(
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          final summary = event['summary'];
          // if event has key dtstart
          final String start = event.containsKey('dtstart') ?  DateFormat('dd.MM.yyyy HH:mm').format(event['dtstart'].toDateTime()): '';
          final location = event['location'] ?? '?';
          return ListTile(
            title: Text(summary),
            subtitle: Text(
              '${start} @ ${location}',
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchIcs,
        child: Icon(Icons.refresh),
        tooltip: 'Termine neu laden',
      ),
    );
  }
}
