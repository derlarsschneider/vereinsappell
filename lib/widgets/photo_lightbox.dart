import 'package:flutter/material.dart';

class PhotoLightbox extends StatefulWidget {
  final List<Map<String, String>> photos;
  final int initialIndex;
  final bool isAdmin;
  final Future<void> Function(String basename) onDelete;

  const PhotoLightbox({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.isAdmin,
    required this.onDelete,
  });

  @override
  State<PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<PhotoLightbox> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onDelete(widget.photos[_currentIndex]['name']!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  widget.photos[i]['photo_url']!,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            if (widget.isAdmin)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: _confirmDelete,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Text(
                '${_currentIndex + 1} / ${widget.photos.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
