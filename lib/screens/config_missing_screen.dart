import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../config_loader.dart';
import '../utils/invite_link.dart';
import 'create_verein_screen.dart';
import 'home_screen.dart';

class ConfigMissingScreen extends StatefulWidget {
  @override
  _ConfigMissingScreenState createState() => _ConfigMissingScreenState();
}

class _ConfigMissingScreenState extends State<ConfigMissingScreen> {
  bool scanning = false;
  bool qrHandled = false;
  final MobileScannerController cameraController = MobileScannerController();
  final ImagePicker _imagePicker = ImagePicker();

  final _inviteLinkController = TextEditingController();
  final _apiBaseUrlController = TextEditingController();
  final _applicationIdController = TextEditingController();
  final _memberIdController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      final url = Uri.base;
      _apiBaseUrlController.text = url.queryParameters['apiBaseUrl'] ?? '';
      _applicationIdController.text = url.queryParameters['applicationId'] ?? '';
      _memberIdController.text = url.queryParameters['memberId'] ?? '';
      _passwordController.text = url.queryParameters['password'] ?? '';
    }
    catch (e) {
      print(e);
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    _inviteLinkController.dispose();
    _apiBaseUrlController.dispose();
    _applicationIdController.dispose();
    _memberIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void handleQRCode(String data) async {
    if (qrHandled) return;
    qrHandled = true;

    String? apiBaseUrl;
    String? applicationId;
    String? memberId;

    // Try URL format first (current QR code format)
    final parsed = parseInviteLink(data);
    if (parsed.isNotEmpty) {
      apiBaseUrl = parsed['apiBaseUrl'];
      applicationId = parsed['applicationId'];
      memberId = parsed['memberId'];
    } else {
      // Fall back to legacy JSON format
      try {
        final jsonData = jsonDecode(data);
        apiBaseUrl = jsonData['apiBaseUrl'];
        applicationId = jsonData['applicationId'];
        memberId = jsonData['memberId'];
      } catch (_) {}
    }

    if (apiBaseUrl != null && applicationId != null && memberId != null) {
      try {
        final config = AppConfig(
          apiBaseUrl: apiBaseUrl,
          applicationId: applicationId,
          memberId: memberId,
        );

        await saveConfig(config);
        final loadedConfig = await loadConfig();

        if (loadedConfig != null) {
          await loadedConfig.member.fetchMember();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider<Member>.value(
                value: loadedConfig.member,
                child: HomeScreen(config: loadedConfig),
              ),
            ),
          );
        } else {
          showError("Konfiguration konnte nicht geladen werden.");
        }
      } catch (e) {
        qrHandled = false;
        showError("Fehler beim Anmelden: $e");
      }
    } else {
      qrHandled = false;
      showError("QR-Code unvollständig.");
    }
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    setState(() => scanning = false);
    qrHandled = false;
  }

  void startQRScan() {
    setState(() {
      scanning = true;
      qrHandled = false;
    });
  }

  Future<void> pickImageAndScanQR() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      // Hier wird das Bild mit mobile_scanner analysiert
      final result = await cameraController.analyzeImage(image.path);

      if (result != null && result.barcodes.isNotEmpty) {
        final String? code = result.barcodes.first.rawValue;
        if (code != null) {
          handleQRCode(code);
        } else {
          showError("Kein QR-Code im Bild gefunden.");
        }
      } else {
        showError("Kein QR-Code im Bild gefunden.");
      }
    } catch (e) {
      showError("Fehler beim Scannen des Bildes: $e");
    }
  }

  void _applyInviteLink(String text) {
    final parsed = parseInviteLink(text);
    if (parsed.isEmpty) return;
    setState(() {
      _apiBaseUrlController.text = parsed['apiBaseUrl']!;
      _applicationIdController.text = parsed['applicationId']!;
      _memberIdController.text = parsed['memberId']!;
      _passwordController.text = parsed['password'] ?? '';
    });
  }

  void handleLogin() async {
    final apiBaseUrl = _apiBaseUrlController.text.trim();
    final applicationId = _applicationIdController.text.trim();
    final memberId = _memberIdController.text.trim();
    final password = _passwordController.text.trim();

    if (apiBaseUrl.isEmpty || applicationId.isEmpty || memberId.isEmpty) {
      showError("Alle Felder müssen ausgefüllt sein.");
      return;
    }

    final config = AppConfig(
      apiBaseUrl: apiBaseUrl,
      applicationId: applicationId,
      memberId: memberId,
      sessionPassword: password.isEmpty ? null : password,
    );

    try {
      await saveConfig(config);
      await config.member.fetchMember();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider<Member>.value(
            value: config.member,
            child: HomeScreen(config: config),
          ),
        ),
      );
    } catch (e) {
      showError("Fehler beim Anmelden: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (scanning) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR-Code scannen')),
        body: MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            final barcode = capture.barcodes.first;
            final String? code = barcode.rawValue;
            if (code != null) {
              cameraController.stop();
              handleQRCode(code);
            }
          },
        ),
      );
    }

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Web-Anmeldung')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _inviteLinkController,
                decoration: const InputDecoration(labelText: 'Einladungslink einfügen'),
                onChanged: _applyInviteLink,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              TextField(
                controller: _apiBaseUrlController,
                decoration: const InputDecoration(labelText: 'API Base URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _applicationIdController,
                decoration: const InputDecoration(labelText: 'Application ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memberIdController,
                decoration: const InputDecoration(labelText: 'Member ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Passwort'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: handleLogin,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                child: const Text('🔐 Anmelden', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: startQRScan,
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                child: const Text('📷 QR-Code scannen', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Willkommen')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚙️ Keine Konfiguration gefunden',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CreateVereinScreen()));
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
              child: const Text('🆕 Neuen Verein anlegen', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: startQRScan,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
              child: const Text('📷 Einem Verein beitreten', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: pickImageAndScanQR,
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
              child: const Text('🖼️ QR-Code aus Bild', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}