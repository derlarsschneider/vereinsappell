// lib/screens/home_screen.dart
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vereins_app_beta/screens/spiess_screen.dart';
import 'package:vereins_app_beta/screens/strafen_screen.dart';

import '../config_loader.dart';
import 'calendar_screen.dart';
import 'default_screen.dart';
import 'galerie_screen.dart';
import 'mitglieder_screen.dart';

class MainMenu extends StatefulWidget {
  final AppConfig config;
  final String appName = 'Schützenlust-Korps Neuss-Gnadental gegr. 1998';

  const MainMenu({required this.config});

  @override
  _MainMenuState createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  Map<String, dynamic>? member;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMember();
  }

  Future<Map<String, dynamic>> fetchMember(String apiBaseUrl, String memberId) async {
    final response = await http.get(Uri.parse('$apiBaseUrl/members/$memberId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Fehler beim Laden');
    }
  }

  Future<void> _loadMember() async {
    try {
      // Beispiel: API-Aufruf, du kannst auch SharedPreferences oder anderes nehmen
      final response = await fetchMember(widget.config.apiBaseUrl, widget.config.memberId);
      setState(() {
        member = response;
        isLoading = false;
      });
    } catch (e) {
      print('Fehler beim Laden des Mitglieds: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Lade...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.appName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Image.asset('assets/images/logo.png', height: 32),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildGridMenu(context),
            const SizedBox(height: 16),
            _buildMemberInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      padding: const EdgeInsets.all(12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // wichtig!
      children: [
        _buildMenuTile(context, '📅 Termine', () => Navigator.push(context, MaterialPageRoute(builder: (_) => CalendarScreen()))),
        _buildMenuTile(context, '📢 Marschbefehl', () => Navigator.push(context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "📢 Marschbefehl", config: widget.config)))),
        _buildMenuTile(context, '💰 Strafen', () => Navigator.push(context, MaterialPageRoute(builder: (_) => StrafenScreen(config: widget.config)))),
        _buildMenuTile(context, '🛡️ Spieß', () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpiessScreen(config: widget.config)))),
        _buildMenuTile(context, '📸 Fotogalerie', () => Navigator.push(context, MaterialPageRoute(builder: (_) => FotogalerieScreen(config: widget.config)))),
        _buildMenuTile(context, '🎲 Knobeln', () => Navigator.push(context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "🎲 Knobeln", config: widget.config)))),
        _buildMenuTile(context, '👥 Mitglieder', () => Navigator.push(context, MaterialPageRoute(builder: (_) => MitgliederScreen(config: widget.config)))),
      ],
    );
  }

  Widget _buildMenuTile(BuildContext context, String title, VoidCallback onTap) {
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
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberInfoCard() {
    if (member == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: GestureDetector(
        onLongPress: () async {
          setState(() => isLoading = true);
          await _loadMember();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mitgliedsdaten aktualisiert')),
          );
        },
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👤 Mitglied: ${member!['name'] ?? 'Unbekannt'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('🛡️ Spieß: ${member!['isSpiess'] == true ? 'Ja' : 'Nein'}'),
                Text('🛠️ Admin: ${member!['isAdmin'] == true ? 'Ja' : 'Nein'}'),
                const SizedBox(height: 4),
                const Text(
                  '🔄 Lange drücken zum Aktualisieren',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
