// lib/screens/marschbefehl_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vereinsappell/screens/default_screen.dart';

import '../api/marschbefehl_api.dart';

class MarschbefehlScreen extends DefaultScreen {

  const MarschbefehlScreen({super.key, required super.config}) : super(title: 'Marschbefehl');

  @override
  DefaultScreenState createState() => _MarschbefehlScreenState();
}

class _MarschbefehlScreenState extends DefaultScreenState<MarschbefehlScreen> {
  late final MarschbefehlApi api;
  List<MarschbefehlEintrag> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    api = MarschbefehlApi(widget.config);
    _fetchMarschbefehl();
  }

  Future<void> _fetchMarschbefehl() async {
    try {
        final List<dynamic> data = await api.fetchMarschbefehl();
        setState(() {
          _items = data
              .map((e) => MarschbefehlEintrag.fromJson(e))
              .toList()
            ..sort((a, b) => a.datetime.compareTo(b.datetime)); // 🔧 Sortieren nach Datum
          _isLoading = false;
        });
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveEntry(DateTime dt, String text, {String? oldDatetime}) async {
    setState(() => _isLoading = true);
    try {
      final iso = dt.toIso8601String();
      if (oldDatetime != null && oldDatetime != iso) {
        await api.deleteMarschbefehl(oldDatetime);
      }
      await api.saveMarschbefehl({
        'datetime': iso,
        'text': text,
      });
      await _fetchMarschbefehl();
      showInfo('Marschbefehl gespeichert');
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEntry(String datetime) async {
    setState(() => _isLoading = true);
    try {
      await api.deleteMarschbefehl(datetime);
      await _fetchMarschbefehl();
      showInfo('Marschbefehl gelöscht');
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddEditDialog([MarschbefehlEintrag? entry]) async {
    final isEdit = entry != null;
    final textController = TextEditingController(text: entry?.text ?? '');
    DateTime selectedDateTime = entry?.datetime ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Marschbefehl bearbeiten' : 'Marschbefehl hinzufügen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text("Datum & Zeit"),
                      subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(selectedDateTime)),
                      trailing: Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDateTime = DateTime(
                                date.year, date.month, date.day,
                                time.hour, time.minute,
                              );
                            });
                          }
                        }
                      },
                    ),
                    TextField(
                      controller: textController,
                      decoration: InputDecoration(labelText: 'Nachricht'),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                if (isEdit)
                  TextButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Löschen?'),
                          content: Text('Soll dieser Eintrag wirklich gelöscht werden?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Abbrechen')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Löschen', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        Navigator.pop(context); // Close edit dialog
                        await _deleteEntry(entry.datetime.toIso8601String());
                      }
                    },
                    child: Text('Löschen', style: TextStyle(color: Colors.red)),
                  ),
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () async {
                    if (textController.text.isNotEmpty) {
                      Navigator.pop(context);
                      await _saveEntry(selectedDateTime, textController.text, oldDatetime: isEdit ? entry.datetime.toIso8601String() : null);
                    }
                  },
                  child: Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.config.member.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📢 Marschbefehl'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: Icon(Icons.add),
              onPressed: () => _showAddEditDialog(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchMarschbefehl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
          itemCount: _items.length,
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final eintrag = _items[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: InkWell(
                onTap: isAdmin ? () => _showAddEditDialog(eintrag) : null,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          eintrag.getFormattedDateTime(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(eintrag.text),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MarschbefehlEintrag {
  final DateTime datetime;
  final String text;

  MarschbefehlEintrag({required this.datetime, required this.text});

  factory MarschbefehlEintrag.fromJson(Map<String, dynamic> json) {
    return MarschbefehlEintrag(
      datetime: DateTime.parse(json['datetime']),
      text: json['text'],
    );
  }

  String getFormattedDateTime() {
    return '${datetime.day.toString().padLeft(2, '0')}.${datetime.month.toString().padLeft(2, '0')}. ${datetime.hour.toString().padLeft(2, '0')}:${datetime.minute.toString().padLeft(2, '0')} Uhr';
  }
}
