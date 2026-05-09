import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vereinsappell/screens/default_screen.dart';
import 'package:vereinsappell/widgets/photo_lightbox.dart';

import '../api/gallery_api.dart';

class GalleryScreen extends DefaultScreen {
  const GalleryScreen({
    super.key,
    required super.config,
  }) : super(title: 'Fotogalerie');

  @override
  DefaultScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends DefaultScreenState<GalleryScreen> {
  late final GalleryApi api;
  List<Map<String, String>> photos = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    api = GalleryApi(widget.config);
    fetchThumbnails();
  }

  Future<void> fetchThumbnails() async {
    setState(() => isLoading = true);
    try {
      final data = await api.fetchThumbnails();
      setState(() => photos = data);
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> uploadPhoto() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (pickedFile == null) return;
    final originalBytes = await pickedFile.readAsBytes();
    setState(() => isLoading = true);
    try {
      await api.uploadPhoto(original: originalBytes, filename: pickedFile.name);
      showInfo('Foto hochgeladen');
      await fetchThumbnails();
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deletePhoto(String basename) async {
    setState(() => isLoading = true);
    try {
      await api.deletePhoto(basename);
      showInfo('Foto gelöscht');
      await fetchThumbnails();
    } catch (e) {
      showError('Fehler: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _openLightbox(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoLightbox(
        photos: photos,
        initialIndex: index,
        isAdmin: widget.config.member.isAdmin,
        onDelete: deletePhoto,
      ),
      fullscreenDialog: true,
    ));
  }

  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 130,
    crossAxisSpacing: 4,
    mainAxisSpacing: 4,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Fotogalerie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: uploadPhoto,
            tooltip: 'Foto hochladen',
          ),
        ],
      ),
      body: isLoading && photos.isEmpty
          ? GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: _gridDelegate,
              itemCount: 12,
              itemBuilder: (_, __) => const _ShimmerTile(),
            )
          : photos.isEmpty
              ? const Center(child: Text('Keine Fotos vorhanden'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: _gridDelegate,
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return GestureDetector(
                      onTap: () => _openLightbox(index),
                      child: Image.network(
                        photo['thumbnail_url']!,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : const _ShimmerTile(),
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ShimmerTile extends StatefulWidget {
  const _ShimmerTile();

  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              Color(0xFF2a2a2a),
              Color(0xFF3d3d3d),
              Color(0xFF2a2a2a),
            ],
          ),
        ),
      ),
    );
  }
}
