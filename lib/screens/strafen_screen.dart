import 'package:auto_size_text/auto_size_text.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:vereinsappell/screens/default_screen.dart';

class StrafenScreen extends DefaultScreen {

  const StrafenScreen({
    super.key,
    required super.config,
  }) : super(title: 'Strafen',);

  @override
  DefaultScreenState createState() => _StrafenScreenState();
}

class _StrafenScreenState extends DefaultScreenState<StrafenScreen> {
  String memberName = '';
  List<dynamic> strafen = [];
  bool isLoading = false;

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
      final finesResponse = await http.get(
        Uri.parse('${widget.config.apiBaseUrl}/fines?memberId=${widget.config.memberId}'),
      );

      if (finesResponse.statusCode == 200) {
        // Response is {"name": "<NAME>, "fines": [...]}
        final Map<String, dynamic> response = json.decode(finesResponse.body);
        final String name = response['name'];
        final List<dynamic> data = response['fines'];
        setState(() {
          strafen = data;
          memberName = name;
        });
      } else {
        showError('Fehler beim Laden: ${finesResponse.statusCode}');
      }
    } catch (e) {
      showError('Fehler beim Abrufen: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _buildStrafeItem(dynamic strafe) {
    return ListTile(
      // leading: Icon(Icons.warning, color: Colors.red),
      title: Text(strafe['reason'] ?? 'Unbekannter Grund'),
      subtitle: Text('Betrag: ${strafe['amount'] ?? '-'} €uro'),
    );
  }

  double getTotalAmount() {
    return strafen.fold(
        0, (sum, item) => sum + (item['amount'] != null ? Decimal.parse(item['amount']).toDouble() : 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AutoSizeText(
          '💰 Strafen von ${memberName}:     ${getTotalAmount().toStringAsFixed(2)} €',
          style: TextStyle(fontSize: 20),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
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
