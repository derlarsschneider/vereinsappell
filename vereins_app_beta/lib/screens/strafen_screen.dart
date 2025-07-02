import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StrafenScreen extends StatefulWidget {
  final String currentUserId;

  const StrafenScreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  _StrafenScreenState createState() => _StrafenScreenState();
}

class _StrafenScreenState extends State<StrafenScreen> {
  List<dynamic> strafen = [];
  bool isLoading = false;
  // final String apiBaseUrl = 'https://your-api-gateway-url.com';
  final String apiBaseUrl = 'http://localhost:5000';

  @override
  void initState() {
    super.initState();
    fetchStrafen();
  }

  Future<void> fetchStrafen() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/fines?memberId=${widget.currentUserId}'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          strafen = data;
        });
      } else {
        print('Fehler beim Laden: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _buildStrafeItem(dynamic strafe) {
    return ListTile(
      leading: Icon(Icons.warning, color: Colors.red),
      title: Text(strafe['reason'] ?? 'Unbekannter Grund'),
      subtitle: Text('Betrag: ${strafe['amount'] ?? '-'} €'),
    );
  }

  double getTotalAmount() {
    return strafen.fold(
        0, (sum, item) => sum + (item['amount'] != null ? item['amount'].toDouble() : 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🛑 Deine Strafen:     ${getTotalAmount().toStringAsFixed(2)} €'),
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
            ? Center(child: CircularProgressIndicator())
            : strafen.isEmpty
            ? Center(child: Text('Keine Strafen vorhanden'))
            : ListView.builder(
              itemCount: strafen.length,
              itemBuilder: (context, index) {
                return _buildStrafeItem(strafen[index]);
              },
            ),
          ),
          FloatingActionButton(
            child: Icon(Icons.refresh),
            onPressed: fetchStrafen,
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
    );
  }
}
