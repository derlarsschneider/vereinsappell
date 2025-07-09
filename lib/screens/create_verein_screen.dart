// lib/screens/create_verein_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config_loader.dart';
import 'home_screen.dart';

class CreateVereinScreen extends StatefulWidget {
  @override
  _CreateVereinScreenState createState() => _CreateVereinScreenState();
}

class _CreateVereinScreenState extends State<CreateVereinScreen> {
  final TextEditingController apiBaseUrlController = TextEditingController();
  final TextEditingController applicationIdController = TextEditingController();
  final TextEditingController memberIdController = TextEditingController();
  bool isAdmin = false;

  Future<void> saveConfig() async {
    final apiBaseUrl = apiBaseUrlController.text.trim();
    final applicationId = applicationIdController.text.trim();
    final memberId = memberIdController.text.trim();

    if (apiBaseUrl.isEmpty || applicationId.isEmpty || memberId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bitte alle Felder ausfüllen')),
      );
      return;
    }

    final config = {
      'apiBaseUrl': apiBaseUrl,
      'applicationId': applicationId,
      'memberId': memberId,
      'isAdmin': isAdmin,
      'appName': 'Mein Schützenverein'
    };

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/config.json');
    await file.writeAsString(jsonEncode(config));

    final loadedConfig = await loadConfigFile();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(config: loadedConfig!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🆕 Neuen Verein anlegen')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView(
          children: [
            TextField(
              controller: apiBaseUrlController,
              decoration: InputDecoration(labelText: 'API Base URL'),
            ),
            TextField(
              controller: applicationIdController,
              decoration: InputDecoration(labelText: 'Application ID'),
            ),
            TextField(
              controller: memberIdController,
              decoration: InputDecoration(labelText: 'Mitglieds-ID'),
            ),
            SizedBox(height: 12),
            CheckboxListTile(
              value: isAdmin,
              onChanged: (val) => setState(() => isAdmin = val ?? false),
              title: Text('Ich bin Administrator'),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(Icons.save),
              label: Text('Konfiguration speichern'),
              onPressed: saveConfig,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
