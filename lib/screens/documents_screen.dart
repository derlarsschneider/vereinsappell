// lib/screens/documents_screen.dart
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config_loader.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';


class DocumentScreen extends StatefulWidget {
  final AppConfig config;

  const DocumentScreen({Key? key, required this.config}) : super(key: key);

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  List<Map<String, dynamic>> documents = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadDocuments();
  }

  Future<void> loadDocuments() async {
    final url = Uri.parse('${widget.config.apiBaseUrl}/docs');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          documents = data.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        throw Exception('Fehler beim Laden der Dokumente');
      }
    } catch (e) {
      showError(e.toString());
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> deleteDocument(String fileName) async {
    final url = Uri.parse('${widget.config.apiBaseUrl}/docs/$fileName');
    final response = await http.delete(url);
    if (response.statusCode == 200) {
      setState(() {
        documents.removeWhere((doc) => doc['title'] == fileName);
      });
    } else {
      showError('Fehler beim Löschen der Datei');
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> uploadDocument() async {
    final fileResult = await FilePicker.platform.pickFiles();
    if (fileResult == null || fileResult.files.isEmpty) return;

    final fileBytes = fileResult.files.single.bytes;
    final originalName = fileResult.files.single.name;

    if (fileBytes == null) {
      showError('Fehler beim Lesen der Datei.');
      return;
    }

    final nameController = TextEditingController(text: originalName);

    // Eingabe für Dateinamen
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Dateiname festlegen"),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: "z.B. Protokoll2025.pdf"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Abbrechen")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text("Hochladen")),
        ],
      ),
    );

    if (accepted != true) return;

    final newName = nameController.text.trim();
    if (newName.isEmpty) {
      showError("Dateiname darf nicht leer sein.");
      return;
    }

    // Prüfen auf Namenskonflikt
    if (documents.any((doc) => doc['title'] == newName)) {
      showError("Es existiert bereits ein Dokument mit diesem Namen.");
      return;
    }

    final uploadUrl = Uri.parse('${widget.config.apiBaseUrl}/docs/$newName');

    try {
      final response = await http.post(
        uploadUrl,
        headers: {'Content-Type': 'application/octet-stream'},
        body: fileBytes,
      );

      if (response.statusCode == 200) {
        await loadDocuments();
      } else {
        showError("Fehler beim Hochladen: ${response.statusCode}");
      }
    } catch (e) {
      showError("Upload fehlgeschlagen: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('📄 Dokumente')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: documents.length,
        itemBuilder: (context, index) {
          final doc = documents[index];
          final title = doc['title'] ?? 'Unbenannt';
          final url = '${widget.config.apiBaseUrl}/docs/$title';
          return ListTile(
            leading: Icon(Icons.picture_as_pdf),
            title: Text(title),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: () => deleteDocument(title),
            ),
            onTap: () {
              if (kIsWeb) {
                // Im neuen Tab öffnen
                // ignore: undefined_prefixed_name
                // web.window.open(url, '_blank');
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PDFViewerScreen(url: url, title: title),
                  ),
                );
              }
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: uploadDocument,
        child: Icon(Icons.upload_file),
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PDFViewerScreen({Key? key, required this.url, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: kIsWeb
            ? SelectableText('📄 PDF wird im neuen Tab geöffnet: $url')
            : Text('📄 PDF Viewer für Mobile hier einbinden.'),
      ),
    );
  }
}
