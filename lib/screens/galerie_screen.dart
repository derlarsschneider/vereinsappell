import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vereinsappell/screens/default_screen.dart';

class GalleryScreen extends DefaultScreen {

  const GalleryScreen({
    super.key,
    required super.config,
  }) : super(title: 'Fotogalerie',);

  @override
  DefaultScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends DefaultScreenState<GalleryScreen> {
  List<Map<String, dynamic>> photos = [];
  final ImagePicker _picker = ImagePicker();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchThumbnails();
  }

  Future<void> fetchPhoto(String name) async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.config.apiBaseUrl}/photos/img/$name'));
      if (response.statusCode == 200) {

        final imageBytes = response.bodyBytes;

        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
        );
      } else {
        showError('Fehler beim Laden des Fotos: ${response.statusCode}');
      }
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchThumbnails() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.config.apiBaseUrl}/photos/thumbnails'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          photos = data.cast<Map<String, dynamic>>();
        });
      } else {
        showError('Fehler beim Laden der Fotos: ${response.statusCode}');
      }
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> uploadPhoto() async {
    final XFile? pickedFile =
    await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile == null) return;

    final originalBytes = await pickedFile.readAsBytes();
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) return;

    final jpegBytes = img.encodeJpg(originalImage, quality: 90);

    final resized = img.copyResize(originalImage, width: 200); // z. B. 800px Breite
    final resizedBytes = img.encodeJpg(resized, quality: 70); // oder encodePng()

    setState(() => isLoading = true);
    final String filename = pickedFile.name.replaceAll(RegExp(r"\.\w+$"), ".jpg");
    try {
      final responseImg = await http.post(
        Uri.parse('${widget.config.apiBaseUrl}/photos'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode([{'file': base64Encode(jpegBytes), 'name': 'img/${filename}'}]),
      );
      final responseThumb = await http.post(
        Uri.parse('${widget.config.apiBaseUrl}/photos'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode([{'file': base64Encode(resizedBytes), 'name': 'thumbnails/${filename}'}]),
      );

      if (responseImg.statusCode == 200 && responseThumb.statusCode == 200) {
        showInfo('Foto hochgeladen');
        fetchThumbnails();
      } else {
        showError('Fehler beim Hochladen: ${responseImg.statusCode}');
      }
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deletePhoto(String photoId) async {
    setState(() => isLoading = true);
    try {
      final response =
      await http.delete(Uri.parse('${widget.config.apiBaseUrl}/photos/$photoId'));

      if (response.statusCode == 200) {
        showInfo('Foto gelöscht');
        fetchThumbnails();
      } else {
        showError('Fehler beim Löschen: ${response.statusCode}');
      }
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fotogalerie'),
        actions: [
          IconButton(
            icon: Icon(Icons.add_a_photo),
            onPressed: uploadPhoto,
            tooltip: 'Foto hochladen',
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : photos.isEmpty
          ? Center(child: Text('Keine Fotos vorhanden'))
          : GridView.builder(
        padding: EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          final thumbnail = photo['file'] as String? ?? '';
          final name = photo['name'] as String? ?? '';

          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => fetchPhoto(name.replaceFirst('thumbnails/', 'img/')),
                child: Image(
                  image: MemoryImage(base64Decode(thumbnail)),
                  fit: BoxFit.cover,
                ),
              ),
              if (widget.config.member.isAdmin)
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text('Foto löschen?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Abbrechen'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                deletePhoto(name);
                              },
                              child: Text(
                                'Löschen',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete, color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
