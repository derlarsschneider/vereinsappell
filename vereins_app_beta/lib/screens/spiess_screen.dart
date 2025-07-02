import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SpiessScreen extends StatefulWidget {
  @override
  _SpiessScreenState createState() => _SpiessScreenState();
}

class _SpiessScreenState extends State<SpiessScreen> {
  // final String apiBaseUrl = 'https://your-api-gateway-url.com';
  final String apiBaseUrl = 'http://localhost:5000';

  List<dynamic> members = [];
  List<dynamic> selectedMemberFines = [];
  String? selectedMemberId;
  String? selectedMemberName;

  final TextEditingController reasonController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  bool isLoadingMembers = false;
  bool isLoadingFines = false;

  @override
  void initState() {
    super.initState();
    fetchMembers();
  }

  Future<void> fetchMembers() async {
    setState(() {
      isLoadingMembers = true;
    });
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/members'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          members = data;
        });
      } else {
        print('Fehler beim Laden der Mitglieder: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen der Mitglieder: $e');
    } finally {
      setState(() {
        isLoadingMembers = false;
      });
    }
  }

  Future<void> fetchFines(String memberId) async {
    setState(() {
      isLoadingFines = true;
      selectedMemberFines.clear();
    });
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/fines?memberId=$memberId'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          selectedMemberFines = data;
        });
      } else {
        print('Fehler beim Laden der Strafen: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen der Strafen: $e');
    } finally {
      setState(() {
        isLoadingFines = false;
      });
    }
  }

  Future<void> addFine(String memberId, String reason, double amount) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/fines'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'memberId': memberId,
          'reason': reason,
          'amount': amount,
        }),
      );

      if (response.statusCode == 200) {
        // Nach erfolgreichem Hinzufügen Strafen neu laden
        await fetchFines(memberId);
        Navigator.of(context).pop(); // Dialog schließen
      } else {
        print('Fehler beim Speichern der Strafe: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern der Strafe')),
        );
      }
    } catch (e) {
      print('Fehler beim Speichern der Strafe: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern der Strafe')),
      );
    }
  }

  void openAddFineDialog() {
    if (selectedMemberId == null) return;

    reasonController.clear();
    amountController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Neue Strafe für $selectedMemberName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              decoration: InputDecoration(labelText: 'Grund'),
            ),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Betrag (€)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (reason.isNotEmpty && amount > 0) {
                addFine(selectedMemberId!, reason, amount);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bitte gültigen Grund und Betrag eingeben')),
                );
              }
            },
            child: Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberItem(dynamic member) {
    final bool isSelected = selectedMemberId == member['id'];
    return ListTile(
      title: Text(member['name'] ?? 'Unbekannt'),
      selected: isSelected,
      onTap: () {
        setState(() {
          selectedMemberId = member['id'];
          selectedMemberName = member['name'];
        });
        fetchFines(member['id']);
      },
    );
  }

  Widget _buildFineItem(dynamic fine) {
    return ListTile(
      leading: Icon(Icons.warning, color: Colors.red),
      title: Text(fine['reason'] ?? 'Unbekannter Grund'),
      trailing: Text('${fine['amount'] ?? '-'} €'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🛡️ Spiess'),
      ),
      body: Row(
        children: [
          // Mitglieder Liste links
          Expanded(
            flex: 2,
            child: isLoadingMembers
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) => _buildMemberItem(members[index]),
            ),
          ),
          VerticalDivider(width: 1),
          // Strafen rechts
          Expanded(
            flex: 3,
            child: selectedMemberId == null
                ? Center(child: Text('Mitglied auswählen'))
                : Column(
              children: [
                Expanded(
                  child: isLoadingFines
                      ? Center(child: CircularProgressIndicator())
                      : selectedMemberFines.isEmpty
                      ? Center(child: Text('Keine Strafen'))
                      : ListView.builder(
                    itemCount: selectedMemberFines.length,
                    itemBuilder: (context, index) =>
                        _buildFineItem(selectedMemberFines[index]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.add),
                    label: Text('Neue Strafe vergeben'),
                    onPressed: openAddFineDialog,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
