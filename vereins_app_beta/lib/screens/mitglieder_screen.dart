import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';

class MitgliederScreen extends StatefulWidget {
  final String apiBaseUrl;
  final String applicationId;

  const MitgliederScreen({
    super.key,
    required this.apiBaseUrl,
    required this.applicationId,
  });

  @override
  State<MitgliederScreen> createState() => _MitgliederScreenState();
}

class _MitgliederScreenState extends State<MitgliederScreen> {
  List<dynamic> mitglieder = [];
  Map<String, dynamic>? selectedMember;
  bool isLoading = false;

  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchMitglieder();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> fetchMitglieder() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.apiBaseUrl}/members'));
      if (response.statusCode == 200) {
        setState(() {
          mitglieder = json.decode(response.body);
        });
      } else {
        print('Fehler beim Laden der Mitglieder: ${response.statusCode}');
      }
    } catch (e) {
      print('Fehler beim Abrufen: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _selectMember(Map<String, dynamic> member) {
    setState(() {
      selectedMember = Map<String, dynamic>.from(member);
      _nameController.text = selectedMember!['name'] ?? '';
    });
  }

  Future<void> saveMember() async {
    if (selectedMember == null) return;

    final url = Uri.parse('${widget.apiBaseUrl}/members');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode(selectedMember);

    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mitglied erfolgreich gespeichert')),
        );
      } else {
        print(body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: ${response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Netzwerkfehler beim Speichern')),
      );
    }
  }

  Widget _buildMemberList() {
    return ListView.builder(
      itemCount: mitglieder.length,
      itemBuilder: (context, index) {
        final member = mitglieder[index];
        return ListTile(
          title: Text(member['name'] ?? 'Unbekannt'),
          onTap: () => _selectMember(member),
        );
      },
    );
  }

  Widget _buildMemberDetail() {
    if (selectedMember == null) {
      return Center(child: Text('Mitglied auswählen'));
    }

    final qrData = json.encode({
      "apiBaseUrl": widget.apiBaseUrl,
      "applicationId": widget.applicationId,
      "memberId": selectedMember!['memberId'],
    });

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mitglieds-ID: ${selectedMember!['memberId']}', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
              onChanged: (value) {
                setState(() {
                  selectedMember!['name'] = value;
                });
              },
            ),
            SwitchListTile(
              title: Text('Admin'),
              value: selectedMember!['isAdmin'] == true,
              onChanged: (val) {
                setState(() {
                  selectedMember!['isAdmin'] = val;
                });
              },
            ),
            SwitchListTile(
              title: Text('Spieß'),
              value: selectedMember!['isSpiess'] == true,
              onChanged: (val) {
                setState(() {
                  selectedMember!['isSpiess'] = val;
                });
              },
            ),
            SizedBox(height: 20),
            Text('QR Code:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Center(
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 180.0,
              ),
            ),
            SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: saveMember,
                icon: Icon(Icons.save),
                label: Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('👥 Mitglieder')),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : _buildMemberList(),
          ),
          VerticalDivider(),
          Expanded(
            flex: 3,
            child: _buildMemberDetail(),
          ),
        ],
      ),
    );
  }
}
