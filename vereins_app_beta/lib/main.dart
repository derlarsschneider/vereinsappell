// lib/main.dart
import 'package:flutter/material.dart';
import 'package:vereins_app_beta/screens/default_screen.dart';
// import 'firebase_push_setup.dart';
// import 'screens/termine_screen.dart';
import 'screens/strafen_screen.dart';
import 'screens/spiess_screen.dart';
import 'screens/galerie_screen.dart';
// import 'screens/knobeln_screen.dart';

// final String apiBaseUrl = 'https://your-api-gateway-url.com';
final String apiBaseUrl = 'http://localhost:5000';
final String currentUserId = '2';
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
      appBar: AppBar(title: Text(appName)),
      body: ListView(
        children: [
          ListTile(
            title: Text('📅 Termine'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "Termine", apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('💰 Strafen'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => StrafenScreen(apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
          ListTile(
            title: Text('🛡️ Spiess'),
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
              context, MaterialPageRoute(builder: (_) => DefaultScreen(title: "Knobeln", apiBaseUrl: apiBaseUrl, currentUserId: currentUserId, isAdmin: isAdmin,)),
            ),
          ),
        ],
      ),
    );
  }
}
