import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:vereinsappell/screens/default_screen.dart';

import '../api/gallery_api.dart';

class GalleryScreen extends DefaultScreen {

  const GalleryScreen({
    super.key,
    required super.config,
  }) : super(title: 'Fotogalerie',);

  @override
  DefaultScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends DefaultScreenState<GalleryScreen> {
  late final GalleryApi api;
  List<Map<String, dynamic>> photos = [];
  final ImagePicker _picker = ImagePicker();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    api = GalleryApi(widget.config);
    fetchThumbnails();
  }

  Future<void> fetchPhoto(String name) async {
    setState(() => isLoading = true);
    try {
        final Uint8List imageBytes = await api.fetchPhoto(name);
        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
        );
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchThumbnails() async {
    setState(() => isLoading = true);
    try {
      final List<dynamic> data = await api.fetchThumbnails();
      setState(() {
        photos = data.cast<Map<String, dynamic>>();
      });
    } catch (e) {
      showError('Fehler Thumbnails: $e');
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

    final resized = img.copyResize(originalImage, width: 200); // z.B. 800px Breite
    final resizedBytes = img.encodeJpg(resized, quality: 70); // oder encodePng()

    setState(() => isLoading = true);
    final String filename = pickedFile.name.replaceAll(RegExp(r"\.\w+$"), ".jpg");
    try {
      await api.uploadPhoto(
        original: jpegBytes,
        thumbnail: resizedBytes,
        filename: filename,
      );
      showInfo('Foto hochgeladen');
      api.fetchThumbnails();
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deletePhoto(String photoId) async {
    setState(() => isLoading = true);
    try {
      api.deletePhoto(photoId);
      showInfo('Foto gelöscht');
      fetchThumbnails();
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
