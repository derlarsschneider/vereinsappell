// lib/screens/home_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'dart:js_interop';


@JS('hardReload')
external JSPromise _jsHardReload();

import 'package:auto_size_text/auto_size_text.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vereinsappell/screens/knobeln_screen.dart';
import 'package:vereinsappell/screens/spiess_screen.dart';
import 'package:vereinsappell/screens/strafen_screen.dart';

import '../api/customers_api.dart';
import '../config_loader.dart';
import '../version.dart';
import '../widgets/pig_overlay.dart';
import 'calendar_screen.dart';
import 'default_screen.dart';
import 'documents_screen.dart';
import 'galerie_screen.dart';
import 'marschbefehl_screen.dart';
import 'mitglieder_screen.dart';

class HomeScreen extends DefaultScreen {
  const HomeScreen({super.key, required super.config}) : super(title: "Home");

  @override
  DefaultScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends DefaultScreenState<HomeScreen> {
  String _applicationName = "Vereins Appell";
  String _applicationLogoBase64 = "";

  @override
  void initState() {
    super.initState();
    _updateApplication();

    try {
      if (kIsWeb) {
        Future<void> futureResponse = widget.config.member.fetchMember();
        futureResponse.whenComplete(() {
          widget.config.member.registerPushSubscriptionWeb();
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            showNotification('${message.data['title']}: ${message.data['body']}');
            if (message.data['type'] == 'fine') {
              showFineOverlay(context);
            } else {
              showPigOverlay(context);
            }
          });
        });
      }
    } catch (e) {
      showError('Fehler beim Registrieren der Push-Subscriptions: $e');
    }
  }

  void _updateApplication() {
    CustomersApi customersApi = CustomersApi(widget.config);
    customersApi.getCustomer(widget.config.applicationId).then((customer) {
      setState(() {
        _applicationName = customer['application_name'];
      });
    }).catchError((error) {
      // Optional: Fehlerbehandlung
      showError("Fehler beim Laden des Vereins: $error");
    });
  }

  Uint8List _decodeBase64(String base64String) {
    // Padding korrigieren, falls notwendig
    int remainder = base64String.length % 4;
    if (remainder != 0) {
      base64String += '=' * (4 - remainder);
    }
    return base64Decode(base64String);
  }


  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _applicationName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          softWrap: true,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: _applicationLogoBase64.isNotEmpty
                ? Image.memory(
              _decodeBase64(_applicationLogoBase64),
              height: 32,
            )
                : Image.asset(
              'assets/images/logo.png',
              height: 32,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildGridMenu(context, member),
            const SizedBox(height: 16),
            _buildMemberInfoCard(context, member),
            if (kDebugMode) _buildDebugButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context, Member member) {
    final tiles = <Widget>[
      _buildMenuTile(
        context,
        '📅 Termine',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CalendarScreen(config: widget.config),
          ),
        ),
      ),
      _buildMenuTile(
        context,
        '📢 Marschbefehl',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MarschbefehlScreen(config: widget.config),
          ),
        ),
      ),
      _buildMenuTile(
        context,
        '💰 Strafen',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StrafenScreen(config: widget.config),
          ),
        ),
      ),
      if (member.isSpiess)
        _buildMenuTile(
          context,
          '🛡️ Spieß',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SpiessScreen(config: widget.config),
            ),
          ),
        ),
      _buildMenuTile(
        context,
        '📄 Dokumente',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentScreen(config: widget.config),
          ),
        ),
      ),
      _buildMenuTile(
        context,
        '📸 Fotogalerie',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GalleryScreen(config: widget.config),
          ),
        ),
      ),
      _buildMenuTile(
        context,
        '🎲 Knobeln',
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                KnobelnScreen(),
          ),
        ),
      ),
      if (member.isAdmin)
        _buildMenuTile(
          context,
          '👥 Mitglieder',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MitgliederScreen(config: widget.config),
            ),
          ),
        ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }

  Widget _buildMenuTile(
    BuildContext context,
    String title,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: AutoSizeText(
              title,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🛠️ Debug', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          OutlinedButton(
            onPressed: () => showPigOverlay(context),
            child: const Text('🐷 Schwein-Animation testen'),
          ),
          const SizedBox(height: 4),
          OutlinedButton(
            onPressed: () => showFineOverlay(context),
            child: const Text('💰 Strafen-Animation testen'),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberInfoCard(BuildContext context, Member member) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: GestureDetector(
        onLongPress: () async {
          try {
            _updateApplication();
            await member.fetchMember();
            if (kIsWeb) {
              await _jsHardReload().toDart;
            } else {
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          } catch (e) {
            showError('Fehler beim Aktualisieren der Mitgliedsdaten: ${e}');
          }
        },
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👤 Mitglied: ${member.name.isNotEmpty ? member.name : widget.config.memberId}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('🛡️ Spieß: ${member.isSpiess ? "Ja" : "Nein"}'),
                Text('🛠️ Admin: ${member.isAdmin ? "Ja" : "Nein"}'),
                const SizedBox(height: 4),
                const Text(
                  '🔄 Lange drücken zum Aktualisieren',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version $appVersion',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
