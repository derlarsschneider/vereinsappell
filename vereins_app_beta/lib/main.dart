// lib/main.dart
import 'package:flutter/material.dart';
// import 'firebase_push_setup.dart';
// import 'screens/termine_screen.dart';
import 'screens/strafen_screen.dart';
import 'screens/spiess_screen.dart';
// import 'screens/fotogalerie_screen.dart';
// import 'screens/knobeln_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await PushNotificationService.initialize();
  runApp(SchuetzenvereinApp());
}

class SchuetzenvereinApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Schützenverein',
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
      appBar: AppBar(title: Text('Schützenverein')),
      body: ListView(
        children: [
          ListTile(
            title: Text('📅 Termine'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => TermineScreen()),
            ),
          ),
          ListTile(
            title: Text('💰 Strafen'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => StrafenScreen(currentUserId: '2')),
            ),
          ),
          ListTile(
            title: Text('🛡️ Spiess'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SpiessScreen()),
            ),
          ),
          ListTile(
            title: Text('📸 Fotogalerie'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => FotogalerieScreen()),
            ),
          ),
          ListTile(
            title: Text('🎲 Knobeln'),
            onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => KnobelnScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class KnobelnScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    throw UnimplementedError();
  }
}

class FotogalerieScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {

    // TODO: implement createState
    throw UnimplementedError();
  }
}

class TermineScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    throw UnimplementedError();
  }
}
