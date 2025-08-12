// lib/screens/mitglieder_screen.dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vereinsappell/screens/default_screen.dart';
import 'package:vereinsappell/api/members_api.dart';

class MitgliederScreen extends DefaultScreen {
  const MitgliederScreen({
    super.key,
    required super.config,
  }) : super(title: 'Mitglieder',);

  @override
  DefaultScreenState createState() => _MitgliederScreenState();
}

class _MitgliederScreenState extends DefaultScreenState<MitgliederScreen> {
  late final MembersApi api;
  List<dynamic> mitglieder = [];
  Map<String, dynamic>? selectedMember;
  bool isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _houseNumberController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phone1Controller = TextEditingController();
  final TextEditingController _phone2Controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    api = MembersApi(widget.config);
    fetchMitglieder();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _streetController.dispose();
    _houseNumberController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _phone1Controller.dispose();
    _phone2Controller.dispose();
    super.dispose();
  }

  Future<void> fetchMitglieder() async {
    setState(() => isLoading = true);
    try {
      mitglieder = await api.fetchMembers();
    } catch (e) {
      showError('$e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _selectMember(Map<String, dynamic> member) {
    setState(() {
      selectedMember = Map<String, dynamic>.from(member);
      _nameController.text = selectedMember!['name'] ?? '';
      _streetController.text = selectedMember!['street'] ?? '';
      _houseNumberController.text = selectedMember!['houseNumber'] ?? '';
      _postalCodeController.text = selectedMember!['postalCode'] ?? '';
      _cityController.text = selectedMember!['city'] ?? '';
      _phone1Controller.text = selectedMember!['phone1'] ?? '';
      _phone2Controller.text = selectedMember!['phone2'] ?? '';
    });
  }

  Future<void> saveMember() async {
    if (selectedMember == null) return;
    try {
      await api.saveMember(selectedMember!);

      // Lokale Liste aktualisieren
      final index = mitglieder.indexWhere((m) => m['memberId'] == selectedMember!['memberId']);
      if (index != -1) {
        mitglieder[index] = Map<String, dynamic>.from(selectedMember!);
      }

      setState(() {}); // UI neu bauen
      showInfo('Mitglied erfolgreich gespeichert');
    } catch (e) {
      showError('$e');
    }
  }

  Future<void> deleteMember() async {
    if (selectedMember == null) return;
    try {
      await api.deleteMember(selectedMember!['memberId']);
      setState(() {
        mitglieder.removeWhere((m) => m['memberId'] == selectedMember!['memberId']);
        selectedMember = null;
      });
      showInfo('Mitglied gelöscht');
    } catch (e) {
      showError('$e');
    }
  }

  Future<void> createMember(String name) async {
    try {
      final newMember = await api.createMember(name, widget.config.applicationId);
      setState(() {
        mitglieder.add(newMember);
      });
      _selectMember(newMember);
    } catch (e) {
      showError('$e');
    }
  }

  Widget _buildMemberList() {
    final TextEditingController _newNameController = TextEditingController();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: mitglieder.length,
            itemBuilder: (context, index) {
              final member = mitglieder[index];
              return ListTile(
                title: Text(member['name'] ?? 'Unbekannt'),
                onTap: () => _selectMember(member),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _newNameController,
            decoration: InputDecoration(
              labelText: 'Neues Mitglied hinzufügen',
              suffixIcon: Icon(Icons.person_add),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              createMember(value);
              _newNameController.clear();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMemberDetail() {
    if (selectedMember == null) {
      return Center(child: Text('Mitglied auswählen'));
    }

    // final qrData = json.encode({
    //   "apiBaseUrl": widget.config.apiBaseUrl,
    //   "applicationId": widget.config.applicationId,
    //   "memberId": selectedMember!['memberId'],
    // });

    final uri = Uri(
      scheme: 'https',
      host: 'vereinsappell.web.app',
      queryParameters: {
        'apiBaseUrl': widget.config.apiBaseUrl,
        'applicationId': widget.config.applicationId,
        'memberId': selectedMember!['memberId'],
      },
    );

    final qrData = uri.toString();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mitglieds-ID: ${selectedMember!['memberId']}', style: TextStyle(fontWeight: FontWeight.bold)),

            // Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
              onChanged: (value) => selectedMember!['name'] = value,
            ),

            // Adresse Block
            SizedBox(height: 20),
            Text('Adresse', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _streetController,
              decoration: InputDecoration(labelText: 'Straße'),
              onChanged: (value) => selectedMember!['street'] = value,
            ),
            TextField(
              controller: _houseNumberController,
              decoration: InputDecoration(labelText: 'Hausnummer'),
              onChanged: (value) => selectedMember!['houseNumber'] = value,
            ),
            TextField(
              controller: _postalCodeController,
              decoration: InputDecoration(labelText: 'PLZ'),
              keyboardType: TextInputType.number,
              onChanged: (value) => selectedMember!['postalCode'] = value,
            ),
            TextField(
              controller: _cityController,
              decoration: InputDecoration(labelText: 'Ort'),
              onChanged: (value) => selectedMember!['city'] = value,
            ),

            // Telefon Block
            SizedBox(height: 20),
            Text('Telefon', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _phone1Controller,
              decoration: InputDecoration(labelText: 'Telefon 1'),
              keyboardType: TextInputType.phone,
              onChanged: (value) => selectedMember!['phone1'] = value,
            ),
            TextField(
              controller: _phone2Controller,
              decoration: InputDecoration(labelText: 'Telefon 2'),
              keyboardType: TextInputType.phone,
              onChanged: (value) => selectedMember!['phone2'] = value,
            ),

            // Rollen
            SizedBox(height: 20),
            SwitchListTile(
              title: Text('Admin'),
              value: selectedMember!['isAdmin'] == true,
              onChanged: (val) => setState(() => selectedMember!['isAdmin'] = val),
            ),
            SwitchListTile(
              title: Text('Spieß'),
              value: selectedMember!['isSpiess'] == true,
              onChanged: (val) => setState(() => selectedMember!['isSpiess'] = val),
            ),

            // QR Code
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

            // Buttons
            SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: saveMember,
                    icon: Icon(Icons.save),
                    label: Text('Speichern'),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Mitglied löschen'),
                          content: Text('Bist du sicher, dass du dieses Mitglied löschen willst?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text('Abbrechen'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                deleteMember();
                              },
                              child: Text('Löschen'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: Icon(Icons.delete),
                    label: Text('Löschen'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
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
