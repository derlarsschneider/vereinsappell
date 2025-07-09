import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

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

  @override
  void dispose() {
    cameraController.dispose();
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
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/config.json');

        final config = {
          'apiBaseUrl': apiBaseUrl,
          'applicationId': applicationId,
          'memberId': memberId,
        };

        await file.writeAsString(jsonEncode(config));
        final loadedConfig = await loadConfigFile();

        if (loadedConfig != null) {
          await loadedConfig.member.fetchMember(); // <--- WICHTIG!
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
      showError("Ungültiger QR-Code.");
    }
    sleep(Duration(seconds: 5));
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

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
    );
  }
}
