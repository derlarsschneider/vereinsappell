import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class DocumentApi {
  final AppConfig config;
  final http.Client _client;

  DocumentApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Uri _docsUrl([String? filename]) {
    if (filename == null) return Uri.parse('${config.apiBaseUrl}/docs');
    // Encode each path segment individually so slashes (for categories) pass through
    final encoded = filename.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('${config.apiBaseUrl}/docs/$encoded');
  }

  Map<String, String> _authHeaders() {
    return headers(config);
  }

  /// Lädt alle Dokumente von der API.
  Future<List<Map<String, dynamic>>> fetchDocuments() async {
    final response = await _client.get(
      _docsUrl(),
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else if (response.statusCode == 401) {
      throw Exception("Falsches Passwort oder Zugriff verweigert.");
    } else {
      throw Exception("Fehler beim Laden der Dokumente (${response.statusCode}).");
    }
  }

  /// Löscht ein Dokument mit dem angegebenen Dateinamen.
  Future<void> deleteDocument(String fileName) async {
    final response = await _client.delete(
      _docsUrl(fileName),
      headers: _authHeaders(),
    );
    if (response.statusCode == 401) {
      throw Exception("Falsches Passwort oder Zugriff verweigert.");
    }
    if (response.statusCode != 200) {
      throw Exception("Fehler beim Löschen: ${response.statusCode}");
    }
  }

  /// Lädt ein Dokument mit dem angegebenen Dateinamen.
  Future<Uint8List> downloadDocument(String fileName) async {
    final response = await _client.get(
      _docsUrl(fileName),
      headers: _authHeaders(),
    );
    if (response.statusCode == 401) {
      throw Exception("Falsches Passwort oder Zugriff verweigert.");
    }
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

    final response = await _client.post(
      _docsUrl(),
      headers: _authHeaders(),
      body: body,
    );

    if (response.statusCode == 401) {
      throw Exception("Falsches Passwort oder Zugriff verweigert.");
    }

    if (response.statusCode != 200) {
      throw Exception("Upload fehlgeschlagen: ${response.statusCode}");
    }
  }

  /// Ruft den Download-URL eines Dokuments ab
  String getDownloadUrl(String fileName) => _docsUrl(fileName).toString();
}
