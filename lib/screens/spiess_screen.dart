import 'package:auto_size_text/auto_size_text.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:vereins_app_beta/screens/default_screen.dart';

class SpiessScreen extends DefaultScreen {

  const SpiessScreen({
    super.key,
    required super.config,
  }) : super(title: 'Spieß',);

  @override
  DefaultScreenState createState() => _SpiessScreenState();
}

class _SpiessScreenState extends DefaultScreenState<SpiessScreen> {
  List<dynamic> members = [];
  List<dynamic> selectedMemberFines = [];
  String? selectedMemberId;
  String? selectedMemberName;

  final TextEditingController reasonController = TextEditingController();

  bool isLoadingMembers = false;
  bool isLoadingFines = false;
  int? selectedAmount = 1;

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
      final response = await http.get(Uri.parse('${widget.config.apiBaseUrl}/members'));
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
      final finesResponse = await http.get(Uri.parse('${widget.config.apiBaseUrl}/fines?memberId=$memberId'));
      if (finesResponse.statusCode == 200) {
        final Map<String, dynamic> response = json.decode(finesResponse.body);
        final String name = response['name'];
        final List<dynamic> data = response['fines'];
        setState(() {
          selectedMemberFines = data;
        });
      } else {
        print('Fehler beim Laden der Strafen: ${finesResponse.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen der Strafen: $e');
    } finally {
      setState(() {
        isLoadingFines = false;
      });
    }
  }

  Future<void> addFine(String memberId, String reason, double amount, BuildContext dialogContext) async {
    try {
      // Float types are not supported. Use Decimal types instead
      final decimalAmount = Decimal.parse(amount.toString());
      // Generate a unique ID for the fine
      final fineId = DateTime.now().millisecondsSinceEpoch.toString();
      final response = await http.post(
        Uri.parse('${widget.config.apiBaseUrl}/fines'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fineId': fineId,
          'memberId': memberId,
          'reason': reason,
          'amount': decimalAmount,
        }),
      );

      if (response.statusCode == 200) {
        await fetchFines(memberId);
        Navigator.of(dialogContext).pop(); // <- nur den Dialog schließen
      } else {
        print(response.body);
        print(response.headers);
        print('Fehler beim Speichern der Strafe: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern der Strafe')),
        );
      }
    } catch (e) {
      print('Fehler beim Speichern der Strafe: $e');
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern der Strafe')),
      );
    }
  }

  Future<void> deleteFine(String fineId) async {
    try {
      final response = await http.delete(Uri.parse('${widget.config.apiBaseUrl}/fines/$fineId'));

      if (response.statusCode == 200) {
        if (selectedMemberId != null) {
          await fetchFines(selectedMemberId!);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Strafe gelöscht')),
        );
      } else {
        print('Fehler beim Löschen der Strafe: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen')),
        );
      }
    } catch (e) {
      print('Fehler beim Löschen: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen')),
      );
    }
  }

  void openAddFineDialog() {
    if (selectedMemberId == null) return;
    selectedAmount = 1;

    // Vorschlagsliste für Gründe
    final List<String> reasons = [
      'Unpünktlichkeit',
      'Falsche Kleidung',
      'Unangebrachtes Verhalten',
      'Nicht erschienen',
      'Sonstiges',
    ];
    String? selectedReason = reasons.first;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Neue Strafe für $selectedMemberName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: InputDecoration(labelText: 'Grund'),
                items: reasons.map((reason) {
                  return DropdownMenuItem(
                    value: reason,
                    child: Text(reason),
                  );
                }).toList(),
                onChanged: (value) {
                  setStateDialog(() {
                    selectedReason = value;
                  });
                },
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [1, 2, 5, 10].map((euro) {
                  final isSelected = selectedAmount == euro;
                  return ChoiceChip(
                    label: Text('€$euro'),
                    selected: isSelected,
                    selectedColor: Colors.blue,
                    onSelected: (_) {
                      setStateDialog(() {
                        selectedAmount = euro;
                      });
                    },
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(), // <- Wichtig!
              child: Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                final reason = selectedReason ?? '';
                final amount = selectedAmount?.toDouble();
                if (reason.isNotEmpty && amount != null && amount > 0) {
                  addFine(selectedMemberId!, reason, amount, dialogContext); // <-- neu
                }
              },
              child: Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberItem(dynamic member) {
    final bool isSelected = selectedMemberId == member['id'];
    return ListTile(
      title: AutoSizeText(
        member['name'] ?? 'Unbekannt',
        maxLines: 1,
      ),
      selected: isSelected,
      onTap: () {
        setState(() {
          selectedMemberId = member['memberId'];
          selectedMemberName = member['name'];
        });
        fetchFines(member['memberId']);
      },
    );
  }

  Widget _buildFineItem(dynamic fine) {
    return ListTile(
      // leading: Icon(Icons.warning, color: Colors.red),
      title: Text(fine['reason'] ?? 'Unbekannter Grund'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${fine['amount'] ?? '-'} €'),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.grey),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Strafe löschen'),
                  content: Text('Möchtest du diese Strafe wirklich löschen?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Abbrechen'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        deleteFine(fine['id']);
                      },
                      child: Text('Löschen'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🛡️ Spieß'),
      ),
      body: Row(
        children: [
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
          Expanded(
            flex: 3,
            child: selectedMemberId == null
                ? Center(child: Text('Mitglied auswählen'))
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    selectedMemberName!,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
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
