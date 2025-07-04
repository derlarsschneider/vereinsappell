import 'package:flutter/material.dart';

class DefaultScreen extends StatefulWidget {
  final String title;
  final String apiBaseUrl;
  final String memberId;
  final bool isAdmin;

  const DefaultScreen({
    Key? key,
    required this.title,
    required this.apiBaseUrl,
    required this.memberId,
    required this.isAdmin,
  }) : super(key: key);

  @override
  DefaultScreenState createState() => DefaultScreenState();
}

class DefaultScreenState<S extends DefaultScreen> extends State<S> {
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
    );
  }
}
