// lib/screens/strafgelder_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StrafgelderScreen extends StatefulWidget {
  @override
  _StrafgelderScreenState createState() => _StrafgelderScreenState();
}

class _StrafgelderScreenState extends State<StrafgelderScreen> {
  final Map<String, List<Map<String, dynamic>>> strafgelderByMember = {};
  final bool isSpiess = true; // ⛳ Dummy für Spießrolle (true = hat Rechte)

  final TextEditingController memberController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();

  // final String apiBaseUrl = 'https://your-api-gateway-url.com';
  final String apiBaseUrl = 'http://localhost:5000';

  @override
  void initState() {
    super.initState();
    fetchStrafgelder();
  }

  Future<void> fetchStrafgelder() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/fines/all'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          strafgelderByMember.clear();
          for (var item in data) {
            final member = item['memberId'] ?? '';
            final fine = {
              'id': item['id'], // eindeutige ID des Strafgeldes
              'reason': item['reason'] ?? '',
            };
            if (!strafgelderByMember.containsKey(member)) {
              strafgelderByMember[member] = [];
            }
            strafgelderByMember[member]!.add(fine);
          }
        });
      } else {
        print('Fehler beim Laden: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen: $e');
    }
  }

  Future<void> addStrafgeld(String member, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/fines'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'memberId': member, 'reason': reason}),
      );

      if (response.statusCode == 200) {
        await fetchStrafgelder();
      } else {
        print('Fehler beim Speichern: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Speichern: $e');
    }
    memberController.clear();
    reasonController.clear();
  }

  Future<void> updateStrafgeld(String id, String newReason) async {
    try {
      final response = await http.put(
        Uri.parse('$apiBaseUrl/fines/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'reason': newReason}),
      );

      if (response.statusCode == 200) {
        await fetchStrafgelder();
      } else {
        print('Fehler beim Aktualisieren: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Aktualisieren: $e');
    }
  }

  Future<void> deleteStrafgeld(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/fines/$id'),
      );

      if (response.statusCode == 200) {
        await fetchStrafgelder();
      } else {
        print('Fehler beim Löschen: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Löschen: $e');
    }
  }

  void openAddDialog() {
    memberController.clear();
    reasonController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Strafgeld vergeben'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: memberController,
              decoration: InputDecoration(labelText: 'Mitglied'),
            ),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(labelText: 'Grund'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              addStrafgeld(memberController.text, reasonController.text);
              Navigator.pop(context);
            },
            child: Text('Vergabe'),
          )
        ],
      ),
    );
  }

  void openEditDialog(String id, String currentReason) {
    reasonController.text = currentReason;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Strafgeld bearbeiten'),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(labelText: 'Grund'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              updateStrafgeld(id, reasonController.text);
              Navigator.pop(context);
            },
            child: Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('💰 Strafgelder')),
      body: ListView(
        children: strafgelderByMember.entries.map((entry) {
          final member = entry.key;
          final fines = entry.value;
          return ExpansionTile(
            title: Text(member),
            children: fines.map((fine) {
              return ListTile(
                title: Text(fine['reason'] ?? ''),
                trailing: isSpiess
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit),
                            onPressed: () {
                              openEditDialog(fine['id'], fine['reason']);
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete),
                            onPressed: () {
                              deleteStrafgeld(fine['id']);
                            },
                          ),
                        ],
                      )
                    : null,
              );
            }).toList(),
          );
        }).toList(),
      ),
      floatingActionButton: isSpiess
          ? FloatingActionButton(
              onPressed: openAddDialog,
              child: Icon(Icons.add),
              tooltip: 'Strafgeld vergeben',
            )
          : null,
    );
  }
}
