// lib/screens/documents_screen.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:vereinsappell/screens/default_screen.dart';

import '../api/documents_api.dart';
import '../logic/documents_logic.dart';

class DocumentScreen extends DefaultScreen {
  final DocumentApi? documentApi;

  const DocumentScreen({super.key, required super.config, this.documentApi})
      : super(title: 'Dokumente');

  @override
  DefaultScreenState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends DefaultScreenState<DocumentScreen> {
  late final DocumentApi api;
  // Map von Kategorie → Dateinamen (nur der letzte Teil ohne Kategorie-Prefix)
  Map<String, List<String>> _grouped = {};
  @override
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    api = widget.documentApi ?? DocumentApi(widget.config);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensurePassword();
      await fetchDocuments();
    });
  }

  // ─── Passwort ─────────────────────────────────────────────────────────────

  Future<void> _ensurePassword() async {
    if (widget.config.sessionPassword != null &&
        widget.config.sessionPassword!.isNotEmpty) return;
    await _askForPassword();
  }

  Future<void> _askForPassword() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Passwort eingeben'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Passwort'),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      widget.config.sessionPassword = controller.text.trim();
    }
  }

  // ─── Daten ────────────────────────────────────────────────────────────────

  Future<void> fetchDocuments() async {
    setState(() => isLoading = true);
    try {
      final result = await api.fetchDocuments();
      setState(() => _grouped = groupDocuments(result));
    } catch (e) {
      if (e.toString().contains('Falsches Passwort') ||
          e.toString().contains('401')) {
        widget.config.sessionPassword = null;
        showError('Falsches Passwort – bitte erneut eingeben.');
        await _askForPassword();
        if (widget.config.sessionPassword != null &&
            widget.config.sessionPassword!.isNotEmpty) {
          await fetchDocuments();
        }
      } else {
        showError('Fehler beim Laden der Dokumente: $e');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _fullName(String category, String shortName) =>
      fullDocumentName(category, shortName);

  List<String> get _existingCategories =>
      _grouped.keys.where((k) => k.isNotEmpty).toList();

  // ─── Aktionen ─────────────────────────────────────────────────────────────

  Future<void> deleteDocument(String category, String shortName) async {
    if (!widget.config.member.isAdmin) return;
    final full = _fullName(category, shortName);
    setState(() => isLoading = true);
    try {
      await api.deleteDocument(full);
      setState(() {
        _grouped[category]?.remove(shortName);
        if (_grouped[category]?.isEmpty ?? false) _grouped.remove(category);
      });
    } catch (e) {
      showError('Fehler beim Löschen: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> previewOrDownload(String category, String shortName) async {
    final full = _fullName(category, shortName);
    try {
      final isPdf = shortName.toLowerCase().endsWith('.pdf');

      if (kIsWeb) {
        // Open tab before await — popup blockers block window.open after async ops
        final newTab = isPdf ? html.window.open('', '_blank') : null;
        final bytes = await api.downloadDocument(full);
        if (isPdf) {
          final blob = html.Blob([bytes], 'application/pdf');
          final url = html.Url.createObjectUrlFromBlob(blob);
          newTab?.location.href = url;
        } else {
          final base64Data = base64Encode(bytes);
          final blobUrl = 'data:application/octet-stream;base64,$base64Data';
          (html.AnchorElement(href: blobUrl)
            ..setAttribute('download', shortName))
            .click();
        }
      } else {
        final bytes = await api.downloadDocument(full);
        final dir = await getTemporaryDirectory();
        final file = io.File('${dir.path}/$shortName');
        await file.writeAsBytes(bytes);
        if (io.Platform.isIOS) {
          // open_file uses UIDocumentInteractionController which silently fails
          // on iOS with Flutter's view hierarchy; share_plus is reliable
          await Share.shareXFiles([XFile(file.path)]);
        } else {
          final result = await OpenFile.open(file.path);
          if (result.type != ResultType.done) {
            showError('Konnte Datei nicht öffnen: ${result.message}');
          }
        }
      }
    } catch (e) {
      showError('Fehler: $e');
    }
  }

  Future<void> uploadDocument() async {
    final fileResult = await FilePicker.platform.pickFiles(withData: true);
    if (fileResult == null || fileResult.files.isEmpty) return;

    final file = fileResult.files.single;
    final fileBytes = file.bytes;
    if (fileBytes == null) {
      showError('Fehler beim Lesen der Datei.');
      return;
    }

    final nameController = TextEditingController(text: file.name);
    final categoryController = TextEditingController();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dokument hochladen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Dateiname'),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (value) => _existingCategories.where(
                (c) => c.toLowerCase().contains(value.text.toLowerCase()),
              ),
              onSelected: (v) => categoryController.text = v,
              fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) {
                ctrl.text = categoryController.text;
                ctrl.addListener(() => categoryController.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Kategorie (optional)',
                    hintText: 'z.B. Protokolle',
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hochladen'),
          ),
        ],
      ),
    );

    if (accepted != true) return;

    final shortName = nameController.text.trim();
    final category = categoryController.text.trim();
    if (shortName.isEmpty) {
      showError('Dateiname darf nicht leer sein.');
      return;
    }
    final fullName = category.isEmpty ? shortName : '$category/$shortName';

    final allNames = _grouped.entries
        .expand((e) => e.value.map((n) => _fullName(e.key, n)))
        .toList();
    if (allNames.contains(fullName)) {
      showError('Ein Dokument mit diesem Namen existiert bereits.');
      return;
    }

    try {
      await api.uploadDocument(name: fullName, fileBytes: fileBytes);
      await fetchDocuments();
    } catch (e) {
      showError('Upload fehlgeschlagen: $e');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📄 Dokumente'),
        actions: [
          if (widget.config.member.isAdmin)
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: uploadDocument,
              tooltip: 'Dokument hochladen',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _grouped.isEmpty
              ? const Center(child: Text('Keine Dokumente vorhanden.'))
              : ListView(
                  children: _grouped.entries.map((entry) {
                    final category = entry.key;
                    final files = entry.value;
                    final title = category.isEmpty ? 'Allgemein' : category;
                    return ExpansionTile(
                      initiallyExpanded: true,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      children: files.map((shortName) {
                        final isPdf = shortName.toLowerCase().endsWith('.pdf');
                        return ListTile(
                          leading: Icon(isPdf
                              ? Icons.picture_as_pdf
                              : Icons.insert_drive_file),
                          title: Text(shortName),
                          trailing: widget.config.member.isAdmin
                              ? IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Dokument löschen?'),
                                        content: Text(shortName),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Abbrechen'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Löschen',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      await deleteDocument(category, shortName);
                                    }
                                  },
                                )
                              : null,
                          onTap: () => previewOrDownload(category, shortName),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
    );
  }
}
