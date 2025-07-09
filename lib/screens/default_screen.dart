import 'package:flutter/material.dart';

import '../config_loader.dart';

class DefaultScreen extends StatefulWidget {
  final String title;
  final AppConfig config;

  const DefaultScreen({
    super.key,
    required this.config,
    required this.title,
  });

  @override
  DefaultScreenState createState() => DefaultScreenState();
}

class DefaultScreenState<T extends DefaultScreen> extends State<T> {
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
    );
  }

  void showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
      ),
    );
  }
}
