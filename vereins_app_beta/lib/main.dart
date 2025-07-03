// lib/main.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:vereins_app_beta/screens/calendar_screen.dart';
import 'package:vereins_app_beta/screens/default_screen.dart';
// import 'firebase_push_setup.dart';
// import 'screens/termine_screen.dart';
import 'screens/strafen_screen.dart';
import 'screens/spiess_screen.dart';
import 'screens/galerie_screen.dart';
// import 'screens/knobeln_screen.dart';

// final String apiBaseUrl = 'http://localhost:5000';
final String apiBaseUrl = 'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com';
final String app = 'vereins-app-beta';
final String memberId = 'm2';
final String currentUserId = '${memberId}';
final bool isAdmin = true;
final String appName = 'Schützenlust-Korps Neuss-Gnadental gegr. 1998';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await PushNotificationService.initialize();
  runApp(SchuetzenvereinApp());
}

class SchuetzenvereinApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainMenu(),
    );
  }
}

class MainMenu extends StatelessWidget {
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
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "📢 Marschbefehl", apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('💰 Strafen'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => StrafenScreen(apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('🛡️ Spieß'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SpiessScreen(apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('📸 Fotogalerie'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => FotogalerieScreen(apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('🎲 Knobeln'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "🎲 Knobeln", apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
        ],
      ),
    );
  }
}
