import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config_loader.dart';
import 'headers.dart';

class GalleryApi {
  final AppConfig config;
  final http.Client _client;

  GalleryApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Map<String, String>>> fetchThumbnails() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/photos/thumbnails'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((e) => {
        'name': e['name'] as String,
        'thumbnail_url': e['thumbnail_url'] as String,
        'photo_url': e['photo_url'] as String,
      }).toList();
    } else {
      throw Exception('Fehler beim Laden der Fotos: ${response.statusCode}');
    }
  }

  Future<void> uploadPhoto({
    required Uint8List original,
    required String filename,
  }) async {
    final basename = filename.contains('.')
        ? '${filename.substring(0, filename.lastIndexOf('.'))}.jpg'
        : '$filename.jpg';
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/photos'),
      headers: headers(config),
      body: json.encode({'file': base64Encode(original), 'name': basename}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Hochladen: ${response.statusCode}');
    }
  }

  Future<void> deletePhoto(String basename) async {
    final response = await _client.delete(
      Uri.parse('${config.apiBaseUrl}/photos/$basename'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
