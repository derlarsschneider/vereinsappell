// lib/screens/marschbefehl_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📢 Marschbefehl')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
