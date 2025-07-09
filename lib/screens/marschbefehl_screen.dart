// lib/screens/marschbefehl_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vereinsappell/screens/default_screen.dart';

class MarschbefehlScreen extends DefaultScreen {

  const MarschbefehlScreen({super.key, required super.config}) : super(title: 'Marschbefehl');

  @override
  DefaultScreenState createState() => _MarschbefehlScreenState();
}

class _MarschbefehlScreenState extends DefaultScreenState<MarschbefehlScreen> {
  List<MarschbefehlEintrag> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMarschbefehl();
  }

  Future<void> _fetchMarschbefehl() async {
    try {
      final response = await http.get(Uri.parse('${widget.config.apiBaseUrl}/marschbefehl'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _items = data
              .map((e) => MarschbefehlEintrag.fromJson(e))
              .toList()
            ..sort((a, b) => a.datetime.compareTo(b.datetime)); // 🔧 Sortieren nach Datum
          _isLoading = false;
        });
      } else {
        throw Exception('Fehler beim Laden der Daten: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📢 Marschbefehl')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Fehler: $_error'))
          : ListView.builder(
        itemCount: _items.length,
        padding: const EdgeInsets.all(12),
        itemBuilder: (context, index) {
          final eintrag = _items[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
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
          );
        },
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
