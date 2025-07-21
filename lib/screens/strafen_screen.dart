import 'package:auto_size_text/auto_size_text.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:vereinsappell/api/fines_api.dart';
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
  late final FinesApi api;
  String memberName = '';
  List<dynamic> strafen = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    api = FinesApi(widget.config);
    fetchStrafen();
  }

  Future<void> fetchStrafen() async {
    setState(() {
      isLoading = true;
    });

    try {
      final Map<String, dynamic> response = await api.fetchFines(widget.config.memberId);
      final String name = response['name'];
      final List<dynamic> fines = response['fines'];
        setState(() {
          strafen = fines;
          memberName = name;
        });
    } catch (e) {
      showError('$e');
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
