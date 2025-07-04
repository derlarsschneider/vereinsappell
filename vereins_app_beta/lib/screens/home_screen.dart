import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:vereins_app_beta/screens/spiess_screen.dart';
import 'package:vereins_app_beta/screens/strafen_screen.dart';

import '../config_loader.dart';
import 'calendar_screen.dart';
import 'default_screen.dart';
import 'galerie_screen.dart';
import 'mitglieder_screen.dart';

class MainMenu extends StatelessWidget {
  final AppConfig config;
  final String appName = 'Schützenlust-Korps Neuss-Gnadental gegr. 1998';
  final bool isAdmin = true;

  const MainMenu({required this.config});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AutoSizeText(
          appName,
          style: TextStyle(fontSize: 20),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Image.asset(
              'assets/images/logo.png',
              height: 32,
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('📅 Termine'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => CalendarScreen()),
            ),
          ),
          ListTile(
            title: Text('📢 Marschbefehl'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "📢 Marschbefehl", apiBaseUrl: config.apiBaseUrl, memberId: config.memberId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('💰 Strafen'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => StrafenScreen(apiBaseUrl: config.apiBaseUrl, memberId: config.memberId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('🛡️ Spieß'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SpiessScreen(apiBaseUrl: config.apiBaseUrl, memberId: config.memberId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('📸 Fotogalerie'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => FotogalerieScreen(apiBaseUrl: config.apiBaseUrl, memberId: config.memberId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('🎲 Knobeln'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "🎲 Knobeln", apiBaseUrl: config.apiBaseUrl, memberId: config.memberId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('👥 Mitglieder'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MitgliederScreen(
                  apiBaseUrl: config.apiBaseUrl,
                  applicationId: config.applicationId,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
