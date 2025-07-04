import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:vereins_app_beta/screens/default_screen.dart';

class FotogalerieScreen extends DefaultScreen {

  const FotogalerieScreen({
    super.key,
    required super.config,
  }) : super(title: 'Fotogalerie',);

  @override
  DefaultScreenState createState() => _FotogalerieScreenState();
}

class _FotogalerieScreenState extends DefaultScreenState<FotogalerieScreen> {
  List<Map<String, dynamic>> photos = [];
  final ImagePicker _picker = ImagePicker();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    fetchPhotos();
  }

  Future<void> fetchPhotos() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.config.apiBaseUrl}/photos'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          photos = data.cast<Map<String, dynamic>>();
        });
      } else {
        _showMessage('Fehler beim Laden der Fotos: ${response.statusCode}');
      }
    } catch (e) {
      _showMessage('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> uploadPhoto() async {
    final XFile? pickedFile =
    await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.config.apiBaseUrl}/photos'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'imageBase64': base64Image}),
      );

      if (response.statusCode == 200) {
        _showMessage('Foto hochgeladen');
        fetchPhotos();
      } else {
        _showMessage('Fehler beim Hochladen: ${response.statusCode}');
      }
    } catch (e) {
      _showMessage('Fehler: $e');
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
        _showMessage('Foto gelöscht');
        fetchPhotos();
      } else {
        _showMessage('Fehler beim Löschen: ${response.statusCode}');
      }
    } catch (e) {
      _showMessage('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          final photoUrl = photo['url'] as String? ?? '';
          final photoId = photo['id'] as String? ?? '';

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(photoUrl, fit: BoxFit.cover),
              if (widget.config.isAdmin)
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
                                deletePhoto(photoId);
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
