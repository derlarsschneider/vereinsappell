// lib/screens/verein_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../api/customers_api.dart';
import '../config_loader.dart';
import 'default_screen.dart';

const _allScreens = [
  {'key': 'termine', 'label': '📅 Termine'},
  {'key': 'marschbefehl', 'label': '📢 Marschbefehl'},
  {'key': 'strafen', 'label': '💰 Strafen'},
  {'key': 'dokumente', 'label': '📄 Dokumente'},
  {'key': 'galerie', 'label': '📸 Fotogalerie'},
  {'key': 'schere_stein_papier', 'label': '✂️ Schere Stein Papier'},
];

class VereinScreen extends DefaultScreen {
  const VereinScreen({super.key, required super.config})
      : super(title: 'Verein');

  @override
  DefaultScreenState<VereinScreen> createState() => _VereinScreenState();
}

class _VereinScreenState extends DefaultScreenState<VereinScreen> {
  late final CustomersApi _api;

  List<Map<String, dynamic>> _allClubs = [];
  Map<String, dynamic>? _selectedClub;

  final _nameController = TextEditingController();
  final _paypalAccountController = TextEditingController();
  String _logoBase64 = '';
  List<String> _activeScreens =
      _allScreens.map((s) => s['key']!).toList();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = CustomersApi(widget.config);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _paypalAccountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      if (widget.config.member.isSuperAdmin) {
        final clubs = await _api.listCustomers();
        if (!mounted) return;
        setState(() {
          _allClubs = clubs;
          isLoading = false;
        });
        // Pre-select the currently active club if present, otherwise the first.
        final current = clubs.where(
          (c) => c['application_id'] == widget.config.applicationId,
        ).toList();
        if (current.isNotEmpty) {
          _applyClub(current.first);
        } else if (clubs.isNotEmpty) {
          _applyClub(clubs.first);
        }
      } else {
        final club = await _api.getCustomer(widget.config.applicationId);
        if (!mounted) return;
        setState(() => isLoading = false);
        _applyClub(club);
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      showError('Fehler beim Laden: $e');
    }
  }

  void _applyClub(Map<String, dynamic> club) {
    setState(() {
      _selectedClub = club;
      _nameController.text = club['application_name'] ?? '';
      _paypalAccountController.text = club['paypal_account'] ?? '';
      _logoBase64 = club['application_logo'] ?? '';
      final screens = club['active_screens'];
      _activeScreens = screens != null
          ? List<String>.from(screens)
          : _allScreens.map((s) => s['key']!).toList();
    });
  }

  Uint8List? _decodeBase64Safe(String raw) {
    final dataUrlMatch = RegExp(r'^data:[^;]+;base64,').firstMatch(raw);
    if (dataUrlMatch != null) raw = raw.substring(dataUrlMatch.end);
    raw = raw.replaceAll(RegExp(r'\s'), '');
    // remainder==1 is never valid base64 — drop the spurious trailing character
    if (raw.length % 4 == 1) raw = raw.substring(0, raw.length - 1);
    final remainder = raw.length % 4;
    if (remainder != 0) raw += '=' * (4 - remainder);

    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  // Resize and JPEG-compress an image so it fits within DynamoDB's item size limit.
  Uint8List _resizeLogo(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return bytes;
    const maxDim = 256;
    final larger = src.width > src.height ? src.width : src.height;
    final image = larger > maxDim
        ? img.copyResize(src, width: (src.width * maxDim / larger).round())
        : src;
    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() => _logoBase64 = base64Encode(_resizeLogo(bytes)));
  }

  Future<void> _save() async {
    final clubId =
        _selectedClub?['application_id'] ?? widget.config.applicationId;
    setState(() => _saving = true);
    try {
      await _api.updateCustomer(clubId, {
        'application_name': _nameController.text.trim(),
        'paypal_account': _paypalAccountController.text.trim(),
        'application_logo': _logoBase64,
        'active_screens': _activeScreens,
      });
      showInfo('Gespeichert');
    } catch (e) {
      showError('Fehler beim Speichern: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final goalCtrl = TextEditingController();
    final paypalCtrl = TextEditingController();
    String dialogLogo = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Neuen Verein erstellen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration:
                      const InputDecoration(labelText: 'API URL (optional)'),
                ),
                TextField(
                  controller: goalCtrl,
                  decoration: const InputDecoration(labelText: 'Spendenziel (optional)'),
                ),
                TextField(
                  controller: paypalCtrl,
                  decoration: const InputDecoration(labelText: 'PayPal Konto (optional)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('Logo wählen (optional)'),
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final bytes = result.files.first.bytes;
                          if (bytes != null) {
                            setDialogState(() =>
                                dialogLogo = base64Encode(_resizeLogo(bytes)));
                          }
                        }
                      },
                    ),
                    if (dialogLogo.isNotEmpty)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final payload = <String, dynamic>{
                    'application_name': name,
                  };
                  final url = urlCtrl.text.trim();
                  if (url.isNotEmpty) payload['api_url'] = url;
                  final paypal = paypalCtrl.text.trim();
                  if (paypal.isNotEmpty) payload['paypal_account'] = paypal;
                  if (dialogLogo.isNotEmpty) {
                    payload['application_logo'] = dialogLogo;
                  }
                  final created = await _api.createCustomer(payload);
                  setState(() {
                    _allClubs.add(created);
                  });
                  _applyClub(created);

                  // Auto-add the new club as a local account
                  final newMemberId = created['member_id'] as String? ?? '';
                  final newApiBaseUrl =
                      created['api_base_url'] as String? ?? widget.config.apiBaseUrl;
                  final newAppId = created['application_id'] as String?;
                  if (newMemberId.isNotEmpty && newAppId != null && newAppId.isNotEmpty) {
                    await addOrActivateAccount(AppConfig(
                      apiBaseUrl: newApiBaseUrl,
                      applicationId: newAppId,
                      memberId: newMemberId,
                      label: name,
                    ));
                  }

                  showInfo('Verein erstellt');
                } catch (e) {
                  showError('Fehler: $e');
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.config.member;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verein'),
        actions: [
          if (member.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Neuen Verein erstellen',
              onPressed: _showCreateDialog,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (member.isSuperAdmin && _allClubs.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      decoration:
                          const InputDecoration(labelText: 'Verein auswählen'),
                      value: _selectedClub?['application_id'] as String?,
                      items: _allClubs.map((c) {
                        return DropdownMenuItem<String>(
                          value: c['application_id'] as String,
                          child: Text(
                            c['application_name'] as String? ??
                                c['application_id'] as String,
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        final club = _allClubs
                            .firstWhere((c) => c['application_id'] == id);
                        _applyClub(club);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _paypalAccountController,
                    decoration: const InputDecoration(
                      labelText: 'PayPal Konto (E-Mail)',
                      helperText: 'Das PayPal-Konto für Spenden.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_logoBase64.isNotEmpty) ...[
                        if (_decodeBase64Safe(_logoBase64) case final bytes?)
                          Image.memory(
                            bytes,
                            height: 48,
                            errorBuilder: (ctx2, e, stack) => const SizedBox(),
                          ),
                        const SizedBox(width: 8),
                      ],
                      TextButton.icon(
                        icon: const Icon(Icons.image),
                        label: Text(
                            _logoBase64.isEmpty ? 'Logo wählen' : 'Logo ändern'),
                        onPressed: _pickLogo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aktive Screens',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  ..._allScreens.map((screen) {
                    final key = screen['key']!;
                    return SwitchListTile(
                      title: Text(screen['label']!),
                      value: _activeScreens.contains(key),
                      onChanged: (val) {
                        setState(() {
                          if (val) {
                            _activeScreens.add(key);
                          } else {
                            _activeScreens.remove(key);
                          }
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Speichern'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
