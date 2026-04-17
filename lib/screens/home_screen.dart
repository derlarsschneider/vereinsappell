// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:vereinsappell/screens/schere_stein_papier_screen.dart';
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
import 'verein_screen.dart';

@JS('hardReload')
external JSPromise _jsHardReload();

class HomeScreen extends DefaultScreen {
  const HomeScreen({super.key, required super.config}) : super(title: "Home");

  @override
  DefaultScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends DefaultScreenState<HomeScreen> {
  String _applicationName = "Vereins Appell";
  String _applicationLogoBase64 = "";
  List<String>? _activeScreens; // null = show all (backwards compatible)
  StreamSubscription? _messageSubscription;
  List<AppConfig> _allAccounts = [];
  int _activeAccountIndex = 0;

  @override
  void initState() {
    super.initState();
    _updateApplication();
    _allAccounts = loadAllAccounts();
    _activeAccountIndex = getActiveAccountIndex();

    try {
      if (kIsWeb) {
        Future<void> futureResponse = widget.config.member.fetchMember();
        futureResponse.whenComplete(() {
          widget.config.member.registerPushSubscriptionWeb();
          _messageSubscription ??= FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _loadAccounts() {
    setState(() {
      _allAccounts = loadAllAccounts();
      _activeAccountIndex = getActiveAccountIndex();
    });
  }

  void _showAccountSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Verein wechseln',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ..._allAccounts.asMap().entries.map((entry) {
            final i = entry.key;
            final account = entry.value;
            final displayLabel =
                account.label.isNotEmpty ? account.label : account.applicationId;
            return ListTile(
              title: Text(displayLabel),
              trailing: i == _activeAccountIndex
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (i == _activeAccountIndex) return;
                setActiveAccount(i);
                if (kIsWeb) {
                  _jsHardReload();
                } else {
                  if (!mounted) return;
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _updateApplication() {
    CustomersApi customersApi = CustomersApi(widget.config);
    customersApi.getCustomer(widget.config.applicationId).then((customer) {
      setState(() {
        _applicationName = customer['application_name'];
        _applicationLogoBase64 = customer['application_logo'] ?? '';
        final screens = customer['active_screens'];
        if (screens != null) {
          _activeScreens = List<String>.from(screens);
        }
      });
      updateActiveAccountLabel(customer['application_name'] as String? ?? '');
    }).catchError((error) {
      showError("Fehler beim Laden des Vereins: $error");
    });
  }

  bool _isScreenActive(String key) {
    if (_activeScreens == null) return true;
    return _activeScreens!.contains(key);
  }

  Uint8List _decodeBase64(String base64String) {
    final dataUrlMatch = RegExp(r'^data:[^;]+;base64,').firstMatch(base64String);
    if (dataUrlMatch != null) base64String = base64String.substring(dataUrlMatch.end);
    base64String = base64String.replaceAll(RegExp(r'\s'), '');
    if (base64String.length % 4 == 1) base64String = base64String.substring(0, base64String.length - 1);
    final remainder = base64String.length % 4;
    if (remainder != 0) base64String += '=' * (4 - remainder);
    return base64Decode(base64String);
  }


  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);

    if (!member.isActive && !member.isSuperAdmin) {
      return _buildDeactivatedScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: _allAccounts.length > 1
            ? TextButton(
                onPressed: _showAccountSwitcher,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  _applicationName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  softWrap: true,
                ),
              )
            : Text(
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
      if (_isScreenActive('termine'))
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
      if (_isScreenActive('marschbefehl'))
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
      if (_isScreenActive('strafen'))
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
      if (member.isSpiess && _isScreenActive('strafen'))
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
      if (_isScreenActive('dokumente'))
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
      if (_isScreenActive('galerie'))
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
      if (_isScreenActive('schere_stein_papier'))
        _buildMenuTile(
          context,
          '✂️ Schere Stein Papier',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SchereSteinPapierScreen(config: widget.config),
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
      if (member.isAdmin || member.isSuperAdmin)
        _buildMenuTile(
          context,
          '🏛️ Verein',
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VereinScreen(config: widget.config),
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

  Widget _buildDeactivatedScreen() => Scaffold(
        appBar: AppBar(title: const Text('Vereins Appell')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Dein Konto wurde deaktiviert.',
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'Bitte wende dich an den Administrator.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );

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
