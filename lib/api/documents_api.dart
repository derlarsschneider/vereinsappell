import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class DocumentApi {
  final AppConfig config;

  DocumentApi(this.config);

  Uri _docsUrl([String? filename]) =>
      Uri.parse('${config.apiBaseUrl}/docs${filename != null ? '/$filename' : ''}');

  /// Lädt alle Dokumente von der API.
  Future<List<Map<String, dynamic>>> fetchDocuments() async {
    final response = await http.get(
      _docsUrl(),
      headers: headers(config),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      throw Exception("Fehler beim Laden der Dokumente");
    }
  }

  /// Löscht ein Dokument mit dem angegebenen Dateinamen.
  Future<void> deleteDocument(String fileName) async {
    final response = await http.delete(
      _docsUrl(fileName),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception("Fehler beim Löschen: ${response.statusCode}");
    }
  }

  /// Lädt ein Dokument mit dem angegebenen Dateinamen.
  Future<Uint8List> downloadDocument(String fileName) async {
    final response = await http.get(
      _docsUrl(fileName),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception("Fehler beim Download: ${response.statusCode}");
    }
    return response.bodyBytes;
  }

  /// Lädt ein neues Dokument hoch (als Base64-kodiert).
  Future<void> uploadDocument({
    required String name,
    required List<int> fileBytes,
  }) async {
    final body = jsonEncode({
      'name': name,
      'file': base64Encode(fileBytes),
    });

    final response = await http.post(
      _docsUrl(),
      headers: headers(config),
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception("Upload fehlgeschlagen: ${response.statusCode}");
    }
  }

  /// Ruft den Download-URL eines Dokuments ab
  String getDownloadUrl(String fileName) => _docsUrl(fileName).toString();
}
