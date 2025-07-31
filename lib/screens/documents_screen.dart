// lib/screens/documents_screen.dart
import 'dart:convert';
import 'dart:io' as io; // Nur für Mobile

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as universal_html; // für Web-Download
import 'package:vereinsappell/screens/default_screen.dart';

import '../api/documents_api.dart';
import '../config_loader.dart';

class DocumentScreen extends DefaultScreen {
  const DocumentScreen({super.key, required super.config}) : super(title: 'Dokumente');

  @override
  DefaultScreenState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends DefaultScreenState<DocumentScreen> {
  late final DocumentApi api;
  List<Map<String, dynamic>> documents = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    api = DocumentApi(widget.config);
    fetchDocuments();
  }

  Future<void> fetchDocuments() async {
    setState(() => isLoading = true);
    try {
      final result = await api.fetchDocuments();
      setState(() => documents = result);
    } catch (e) {
      showError("Fehler: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteDocument(String fileName) async {
    setState(() => isLoading = true);
    if (widget.config.member.isAdmin) {
      try {
        api.deleteDocument(fileName);
        setState(() {
          documents.removeWhere((doc) => doc['name'] == fileName);
        });
      } catch (e) {
        showError('Fehler beim Löschen der Datei. ${e}');
      } finally {
        setState(() => isLoading = false);
      }
    }
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

    try {
      api.uploadDocument(name: newName, fileBytes: fileBytes);
      await fetchDocuments();
    } catch (e) {
      showError("Upload fehlgeschlagen: $e");
    }
  }

  void downloadFile({required String fileName}) async {
    try {
      final bytes = await api.downloadDocument(fileName);
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
      appBar: AppBar(
        title: Text('📄 Dokumente'),
        actions: [
          IconButton(
            icon: Icon(Icons.upload_file),
            onPressed: uploadDocument,
            tooltip: 'Dokument hochladen',
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: documents.length,
              itemBuilder: (context, index) {
                final doc = documents[index];
                final name = doc['name'] ?? 'Unbenannt';
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
                    downloadFile(fileName: name);
                  },
                );
              },
            ),
    );
  }
}
