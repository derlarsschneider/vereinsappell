import 'package:flutter/material.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:intl/intl.dart';

import '../api/calendar_api.dart';
import 'default_screen.dart';

class CalendarScreen extends DefaultScreen {
  const CalendarScreen({
    super.key,
    required super.config,
  }) : super(title: 'Kalender',);

  @override
  DefaultScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends DefaultScreenState<CalendarScreen> {
  late final CalendarApi api;
  List<Map<String, dynamic>> events = [];
  bool isLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    api = CalendarApi(widget.config);
    fetchIcs();
  }

  Future<void> fetchIcs() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final CalendarApi calendarApi = CalendarApi(widget.config);
      final Map<String, dynamic> calendar = await calendarApi.getCalendar();
      final ICalendar ical = ICalendar.fromString(calendar['ics_content']);
      setState(() {
        events = ical.data;
        events.sort((a, b) {
          final aDate = a['dtstart']?.toDateTime() ?? DateTime(2100);
          final bDate = b['dtstart']?.toDateTime() ?? DateTime(2100);
          return aDate.compareTo(bDate);
        });
      });
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

  Future<void> _showReminderSettings() async {
    bool enabled = widget.config.member.reminderEnabled;
    int hoursBefore = widget.config.member.reminderHoursBefore;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Erinnerungseinstellungen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Erinnerungen aktivieren'),
                value: enabled,
                onChanged: (v) => setDialogState(() => enabled = v),
              ),
              if (enabled) ...[
                const SizedBox(height: 8),
                for (final entry in const {
                  2: '2 Stunden',
                  6: '6 Stunden',
                  24: '1 Tag',
                  48: '2 Tage',
                }.entries)
                  RadioListTile<int>(
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: hoursBefore,
                    onChanged: (v) => setDialogState(() => hoursBefore = v!),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final prevEnabled = widget.config.member.reminderEnabled;
                final prevHours = widget.config.member.reminderHoursBefore;
                widget.config.member.reminderEnabled = enabled;
                widget.config.member.reminderHoursBefore = hoursBefore;
                try {
                  await widget.config.member.saveMember();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) showInfo('Einstellungen gespeichert');
                } catch (e) {
                  widget.config.member.reminderEnabled = prevEnabled;
                  widget.config.member.reminderHoursBefore = prevHours;
                  if (mounted) showError('Fehler beim Speichern: $e');
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📅 Termine'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Erinnerungseinstellungen',
            onPressed: _showReminderSettings,
          ),
        ],
      ),
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
