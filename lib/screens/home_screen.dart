// lib/screens/home_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vereinsappell/screens/spiess_screen.dart';
import 'package:vereinsappell/screens/strafen_screen.dart';

import '../config_loader.dart';
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
  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.config.appName,
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
            child: Image.asset('assets/images/logo.png', height: 32),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildGridMenu(context, member),
            const SizedBox(height: 16),
            _buildMemberInfoCard(context, member),
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
            builder: (_) => CalendarScreen(config: widget.config,)
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
                DefaultScreen(title: "🎲 Knobeln", config: widget.config),
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

  Widget _buildMemberInfoCard(BuildContext context, Member member) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: GestureDetector(
        onLongPress: () async {
          try {
            await member.fetchMember();
            showInfo('Mitgliedsdaten aktualisiert');
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
