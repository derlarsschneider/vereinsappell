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
      final url = Uri.parse(
          'https://www.schuetzenlust-gnadental.de/index.php/termine/eventslist/?format=raw&layout=ics');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final rawIcs = response.body;
        final calendar = ICalendar.fromString(rawIcs);

        setState(() {
          events = calendar.data;
          events.sort((a, b) {
            final aDate = a['dtstart']?.toDateTime() ?? DateTime(2100);
            final bDate = b['dtstart']?.toDateTime() ?? DateTime(2100);
            return aDate.compareTo(bDate);
          });
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

  String formatDateTime(DateTime dt) {
    return DateFormat('dd.MM.yyyy HH:mm \'Uhr\'').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📅 Termine')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : ListView.builder(
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          final title = event['summary'] ?? '';
          final location = event['location'] ?? '';
          final start = event['dtstart']?.toDateTime();

          if (start == null) return const SizedBox.shrink();

          return Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    formatDateTime(start),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500)),
                      if (location.isNotEmpty)
                        Text(location,
                            style:
                            const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchIcs,
        child: const Icon(Icons.refresh),
        tooltip: 'Termine neu laden',
      ),
    );
  }
}
