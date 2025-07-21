import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config_loader.dart';
import 'headers.dart';

class GalleryApi {
  final AppConfig config;

  GalleryApi(this.config);

  Future<List<Map<String, dynamic>>> fetchThumbnails() async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/photos/thumbnails'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Fehler beim Laden der Fotos: ${response.statusCode}');
    }
  }

  Future<Uint8List> fetchPhoto(String name) async {
    final response = await http.get(
      Uri.parse('${config.apiBaseUrl}/photos/img/$name'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Fehler beim Laden des Fotos: ${response.statusCode}');
    }
  }

  Future<void> uploadPhoto({
    required Uint8List original,
    required Uint8List thumbnail,
    required String filename,
  }) async {
    final imgName = 'img/$filename';
    final thumbName = 'thumbnails/$filename';

    final responseImg = await http.post(
      Uri.parse('${config.apiBaseUrl}/photos'),
      headers: headers(config),
      body: json.encode([{'file': base64Encode(original), 'name': imgName}]),
    );
    final responseThumb = await http.post(
      Uri.parse('${config.apiBaseUrl}/photos'),
      headers: headers(config),
      body: json.encode([{'file': base64Encode(thumbnail), 'name': thumbName}]),
    );

    if (responseImg.statusCode != 200 || responseThumb.statusCode != 200) {
      print(responseThumb.body);
      throw Exception('Fehler beim Hochladen. Img: ${responseImg.statusCode}, Thumb: ${responseThumb.statusCode}');
    }
  }

  Future<void> deletePhoto(String name) async {
    final response = await http.delete(
      Uri.parse('${config.apiBaseUrl}/photos/$name'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
