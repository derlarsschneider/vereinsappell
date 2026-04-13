import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../config_loader.dart';
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

  final _apiBaseUrlController = TextEditingController();
  final _applicationIdController = TextEditingController();
  final _memberIdController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      final url = Uri.base;
      _apiBaseUrlController.text = url.queryParameters['apiBaseUrl'] ?? '';
      _applicationIdController.text = url.queryParameters['applicationId'] ?? '';
      _memberIdController.text = url.queryParameters['memberId'] ?? '';
      _passwordController.text = url.queryParameters['password'] ?? '';
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    _apiBaseUrlController.dispose();
    _applicationIdController.dispose();
    _memberIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void handleQRCode(String data) async {
    if (qrHandled) return;
    qrHandled = true;

    try {
      final jsonData = jsonDecode(data);
      final apiBaseUrl = jsonData['apiBaseUrl'];
      final applicationId = jsonData['applicationId'];
      final memberId = jsonData['memberId'];

      if (apiBaseUrl != null && applicationId != null && memberId != null) {
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
      } else {
        showError("QR-Code unvollständig.");
      }
    } catch (e) {
      qrHandled = false; // Scan erneut erlauben nach ungültigem QR-Code
      showError("Ungültiger QR-Code.");
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
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text("Web-Anmeldung")),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _apiBaseUrlController,
                decoration: InputDecoration(labelText: 'API Base URL'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _applicationIdController,
                decoration: InputDecoration(labelText: 'Application ID'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _memberIdController,
                decoration: InputDecoration(labelText: 'Member ID'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Passwort'),
                obscureText: true,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: handleLogin,
                child: Text('🔐 Anmelden', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 60),
                ),
              ),
              SizedBox(height: 12),
              OutlinedButton(
                onPressed: pickImageAndScanQR,
                child: Text('📸 QR-Code aus Bild laden', style: TextStyle(fontSize: 18)),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 60),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (scanning) {
      return Scaffold(
        appBar: AppBar(title: Text('QR-Code scannen')),
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

    return Scaffold(
      appBar: AppBar(title: Text("Willkommen")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('⚙️ Keine Konfiguration gefunden', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CreateVereinScreen()),
                );
              },
              child: Text('🆕 Neuen Verein anlegen', style: TextStyle(fontSize: 20)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: startQRScan,
              child: Text('📷 Einem Verein beitreten', style: TextStyle(fontSize: 20)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
              ),
            ),
            SizedBox(height: 12),
            OutlinedButton(
              onPressed: pickImageAndScanQR,
              child: Text('🖼️ QR-Code aus Bild', style: TextStyle(fontSize: 18)),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}