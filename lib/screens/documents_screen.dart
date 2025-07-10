// lib/screens/documents_screen.dart
import 'dart:convert';
import 'dart:io' as io; // Nur für Mobile

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as universal_html; // für Web-Download

import '../config_loader.dart';

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
    if (widget.config.member.isAdmin) {
      final url = Uri.parse('${widget.config.apiBaseUrl}/docs/$fileName');
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        setState(() {
          documents.removeWhere((doc) => doc['name'] == fileName);
        });
      } else {
        showError('Fehler beim Löschen der Datei');
      }
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> uploadDocument() async {
    final fileResult = await FilePicker.platform.pickFiles(withData: true);
    if (fileResult == null || fileResult.files.isEmpty) return;

    final file = fileResult.files.single;
    final fileBytes = file.bytes;
    final originalName = file.name;

    if (fileBytes == null) {
      showError('Fehler beim Lesen der Datei (null Bytes).');
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Abbrechen"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Hochladen"),
          ),
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
    if (documents.any((doc) => doc['name'] == newName)) {
      showError("Es existiert bereits ein Dokument mit diesem Namen.");
      return;
    }

    final uploadUrl = Uri.parse('${widget.config.apiBaseUrl}/docs');
    print(uploadUrl);

    final body = jsonEncode({
      'name': newName,
      'file': base64Encode(fileBytes), // <-- explizit codieren
    });

    try {
      final response = await http.post(
        uploadUrl,
        headers: {'Content-Type': 'application/octet-stream'},
        body: body,
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

  void downloadFile({required String url}) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        showError("Fehler beim Herunterladen: ${response.statusCode}");
        return;
      }

      final bytes = response.bodyBytes;
      final fileName = Uri.parse(url).pathSegments.last;

      if (kIsWeb) {
        // 🔄 Web: HTML download trigger
        final base64Data = base64Encode(bytes);
        final blobUrl = 'data:application/octet-stream;base64,$base64Data';

        final anchor = universal_html.AnchorElement(href: blobUrl)
          ..setAttribute('download', fileName)
          ..click();
      } else {
        // 📱 Mobile: Datei speichern und öffnen
        final dir = await getTemporaryDirectory();
        final file = io.File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);

        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) {
          showError("Konnte Datei nicht öffnen: ${result.message}");
        }
      }
    } catch (e) {
      showError("Download fehlgeschlagen: $e");
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
                final name = doc['name'] ?? 'Unbenannt';
                final url = '${widget.config.apiBaseUrl}/docs/$name';
                return ListTile(
                  leading: Icon(Icons.file_download),
                  title: Text(name),
                  trailing: widget.config.member.isAdmin
                      ? IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => deleteDocument(name),
                        )
                      : null,
                  onTap: () {
                    downloadFile(url: url);
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
