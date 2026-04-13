import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../config_loader.dart';
import '../storage.dart';

// ─── Datenmodell ────────────────────────────────────────────────────────────

enum _Zug { schere, stein, papier }

const _zugEmoji = {
  _Zug.schere: '✂️',
  _Zug.stein: '🪨',
  _Zug.papier: '✋',
};

_Zug? _zugFromString(String? s) => switch (s) {
      'schere' => _Zug.schere,
      'stein' => _Zug.stein,
      'papier' => _Zug.papier,
      _ => null
    };

String _zugToString(_Zug z) => switch (z) {
      _Zug.schere => 'schere',
      _Zug.stein => 'stein',
      _Zug.papier => 'papier',
    };

/// +1 = a gewinnt, -1 = b gewinnt, 0 = Unentschieden
int _ergebnis(_Zug a, _Zug b) {
  if (a == b) return 0;
  if ((a == _Zug.stein && b == _Zug.schere) ||
      (a == _Zug.schere && b == _Zug.papier) ||
      (a == _Zug.papier && b == _Zug.stein)) {
    return 1;
  }
  return -1;
}

class _Spielstand {
  int siege;
  int niederlagen;
  int unentschieden;

  _Spielstand({this.siege = 0, this.niederlagen = 0, this.unentschieden = 0});

  factory _Spielstand.fromJson(Map<dynamic, dynamic> map) => _Spielstand(
        siege: (map['s'] as int?) ?? 0,
        niederlagen: (map['n'] as int?) ?? 0,
        unentschieden: (map['u'] as int?) ?? 0,
      );

  Map<String, int> toJson() => {'s': siege, 'n': niederlagen, 'u': unentschieden};
}

// ─── Screen ─────────────────────────────────────────────────────────────────

enum _Phase { suche, warte, waehle, bestaetigt, aufdecken, gegnerWeg }

class SchereSteinPapierScreen extends StatefulWidget {
  final AppConfig config;

  const SchereSteinPapierScreen({super.key, required this.config});

  @override
  State<SchereSteinPapierScreen> createState() => _SchereSteinPapierScreenState();
}

class _SchereSteinPapierScreenState extends State<SchereSteinPapierScreen> {
  // ─── Firebase ───────────────────────────────────────────────────────────
  final _db = FirebaseDatabase.instance;

  // ─── Spielzustand ───────────────────────────────────────────────────────
  _Phase _phase = _Phase.suche;
  _Zug? _meineWahl;
  _Zug? _gegnerWahl;
  String _gameId = '';
  String _gegnerId = '';
  String _gegnerName = '';
  bool _gameStarted = false;
  _Spielstand _spielstand = _Spielstand();

  StreamSubscription? _warteSub;
  StreamSubscription? _gameSub;
  Timer? _aufdeckTimer;

  // ─── Shortcuts ──────────────────────────────────────────────────────────
  String get _myId => widget.config.memberId;
  String get _myName =>
      widget.config.member.name.isNotEmpty ? widget.config.member.name : _myId;
  String get _appId => widget.config.applicationId;

  DatabaseReference get _waitingRef => _db.ref('ssp/$_appId/waiting');
  DatabaseReference get _gameRef => _db.ref('ssp/$_appId/games/$_gameId');

  // ─── Lebenszyklus ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  @override
  void dispose() {
    _warteSub?.cancel();
    _gameSub?.cancel();
    _aufdeckTimer?.cancel();
    // Best-effort cleanup – onDisconnect greift als Fallback, falls dies nicht ankommt
    _waitingRef.child(_myId).remove();
    if (_gameId.isNotEmpty) {
      _gameRef.child('connected/$_myId').remove();
    }
    super.dispose();
  }

  // ─── Lokale Spielstandspeicherung ───────────────────────────────────────

  String get _scoreKey => 'ssp_${_appId}_${_myId}_$_gegnerId';

  void _ladeSpielstand() {
    final json = getItem(_scoreKey);
    setState(() {
      _spielstand = json != null
          ? _Spielstand.fromJson(jsonDecode(json) as Map)
          : _Spielstand();
    });
  }

  void _speichereSpielstand() {
    setItem(_scoreKey, jsonEncode(_spielstand.toJson()));
  }

  void _spielstandZuruecksetzen() {
    setItem(_scoreKey, jsonEncode(_Spielstand().toJson()));
    setState(() => _spielstand = _Spielstand());
  }

  // ─── Matchmaking ────────────────────────────────────────────────────────

  // ignore: avoid_print
  void _log(String msg) => print('[SSP:$_myId] $msg');

  Future<void> _startSearch() async {
    _log('_startSearch');
    setState(() => _phase = _Phase.suche);
    _warteSub?.cancel();

    try {
      await _addToWaiting();
      await _tryMatchFromWaitingList();
    } catch (e, st) {
      _log('FEHLER in _startSearch: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Firebase-Fehler: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      ));
    }
  }

  Future<void> _addToWaiting() async {
    _log('_addToWaiting: trage mich ein');
    final ref = _waitingRef.child(_myId);
    await ref.onDisconnect().remove();
    await ref.set({'name': _myName, 'gameId': null});
    _log('_addToWaiting: eingetragen, höre auf gameId');
    if (!mounted) return;
    setState(() => _phase = _Phase.warte);

    _warteSub = ref.onValue.listen((event) {
      if (!mounted || _phase != _Phase.warte) return;
      final data = event.snapshot.value as Map?;
      _log('_warteSub: snapshot = $data');
      if (data == null) return;
      final gameId = data['gameId'] as String?;
      if (gameId != null) {
        _log('_warteSub: gameId erhalten → _joinGame ($gameId)');
        _warteSub?.cancel();
        _gameId = gameId;
        _joinGame();
      }
    });
  }

  Future<void> _tryMatchFromWaitingList() async {
    _log('_tryMatchFromWaitingList: lese Warteliste');
    final snapshot = await _waitingRef.get();
    if (!mounted || _phase != _Phase.warte) {
      _log('_tryMatchFromWaitingList: abgebrochen (phase=$_phase, mounted=$mounted)');
      return;
    }

    final raw = snapshot.value;
    _log('_tryMatchFromWaitingList: Warteliste = $raw');
    if (raw == null) {
      _log('_tryMatchFromWaitingList: leer, warte passiv');
      return;
    }
    final data = Map<Object?, Object?>.from(raw as Map);

    for (final entry in data.entries) {
      final waiterId = entry.key as String;
      if (waiterId == _myId) continue;

      final waiterRaw = entry.value;
      if (waiterRaw == null) continue;
      final waiterData = Map<Object?, Object?>.from(waiterRaw as Map);
      if (waiterData['gameId'] != null) {
        _log('_tryMatchFromWaitingList: $waiterId bereits gematcht, überspringe');
        continue;
      }

      _log('_tryMatchFromWaitingList: versuche $waiterId zu claimen');
      final newGameId = '${DateTime.now().millisecondsSinceEpoch}';

      // Spiel anlegen BEVOR die Transaktion Spieler 1 benachrichtigt,
      // damit _joinGame() das Spiel sofort findet.
      _warteSub?.cancel();
      _gameId = newGameId;
      _gegnerId = waiterId;
      _gegnerName = (waiterData['name'] as String?) ?? waiterId;
      await _waitingRef.child(_myId).remove();
      await _createGame();

      final result =
          await _waitingRef.child(waiterId).runTransaction((currentData) {
        _log('  transaction callback: currentData = $currentData');
        if (currentData == null) return Transaction.success(null);
        final map = Map<Object?, Object?>.from(currentData as Map);
        if (map['gameId'] != null) return Transaction.abort();
        return Transaction.success({...map, 'gameId': newGameId});
      });

      _log('_tryMatchFromWaitingList: transaction committed=${result.committed}');
      if (!mounted) return;

      if (result.committed) {
        _log('_tryMatchFromWaitingList: gematcht mit $waiterId');
        await _waitingRef.child(waiterId).remove();
        return;
      } else {
        // Transaktion fehlgeschlagen – Spieler 1 wurde inzwischen von jemand anderem gematcht.
        // Spiel wieder aufräumen und neu suchen.
        _log('_tryMatchFromWaitingList: Transaktion fehlgeschlagen, räume auf und starte neu');
        _gameSub?.cancel();
        await _gameRef.remove();
        _gameId = '';
        _gegnerId = '';
        _gegnerName = '';
        _startSearch();
        return;
      }
    }
    _log('_tryMatchFromWaitingList: niemanden gefunden, warte passiv');
  }

  // ─── Spielaufbau ────────────────────────────────────────────────────────

  Future<void> _createGame() async {
    _log('_createGame: gameId=$_gameId, gegner=$_gegnerId');
    await _gameRef.set({
      'p1': {'id': _myId, 'name': _myName},
      'p2': {'id': _gegnerId, 'name': _gegnerName},
      'connected': {_myId: true},
      'choices': {_myId: null, _gegnerId: null},
    });
    await _gameRef.child('connected/$_myId').onDisconnect().remove();

    _gameStarted = false;
    _ladeSpielstand();
    _listenToGame();
    setState(() {
      _phase = _Phase.waehle;
      _meineWahl = null;
    });
  }

  Future<void> _joinGame() async {
    _log('_joinGame: gameId=$_gameId');
    final snapshot = await _gameRef.get();
    if (!mounted || !snapshot.exists) {
      _startSearch();
      return;
    }

    final data = snapshot.value as Map;
    final p1 = data['p1'] as Map;
    final p2 = data['p2'] as Map;
    _gegnerId = (p1['id'] == _myId ? p2['id'] : p1['id']) as String;
    _gegnerName = ((p1['id'] == _myId ? p2['name'] : p1['name']) as String?) ?? _gegnerId;

    await _gameRef.child('connected/$_myId').onDisconnect().remove();
    await _gameRef.child('connected/$_myId').set(true);

    _gameStarted = false;
    _ladeSpielstand();
    _listenToGame();
    setState(() {
      _phase = _Phase.waehle;
      _meineWahl = null;
    });
  }

  void _listenToGame() {
    _gameSub?.cancel();
    _gameSub = _gameRef.onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map?;

      if (data == null) {
        if (_gameStarted) setState(() => _phase = _Phase.gegnerWeg);
        return;
      }

      final connected = (data['connected'] as Map?) ?? {};

      // Warten bis beide verbunden sind
      if (!_gameStarted) {
        if (connected[_myId] != null && connected[_gegnerId] != null) {
          _gameStarted = true;
        } else {
          return;
        }
      }

      // Gegner hat die Verbindung getrennt
      if (connected[_gegnerId] == null) {
        _aufdeckTimer?.cancel();
        setState(() => _phase = _Phase.gegnerWeg);
        return;
      }

      // Spielzüge auswerten
      final choices = data['choices'] as Map?;
      final meineWahl = _zugFromString(choices?[_myId] as String?);
      final gegnerWahl = _zugFromString(choices?[_gegnerId] as String?);

      if (meineWahl != null && gegnerWahl != null) {
        if (_phase != _Phase.aufdecken) _aufdecken(meineWahl, gegnerWahl);
      } else if (meineWahl != null) {
        setState(() {
          _phase = _Phase.bestaetigt;
          _meineWahl = meineWahl;
        });
      } else {
        // meineWahl == null in Firebase: entweder neue Runde (nach Aufdecken) oder
        // Gegner hat bestätigt während wir noch lokal gewählt aber noch nicht abgeschickt haben.
        // In letzterem Fall lokale Wahl NICHT zurücksetzen.
        final neueRunde = _phase == _Phase.bestaetigt || _phase == _Phase.aufdecken;
        setState(() {
          _phase = _Phase.waehle;
          if (neueRunde) {
            _meineWahl = null;
            _gegnerWahl = null;
          }
        });
      }
    });
  }

  // ─── Spiellogik ─────────────────────────────────────────────────────────

  Future<void> _wahlBestaetigen() async {
    if (_meineWahl == null) return;
    await _gameRef.child('choices/$_myId').set(_zugToString(_meineWahl!));
  }

  void _aufdecken(_Zug meineWahl, _Zug gegnerWahl) {
    setState(() {
      _phase = _Phase.aufdecken;
      _meineWahl = meineWahl;
      _gegnerWahl = gegnerWahl;
    });

    final e = _ergebnis(meineWahl, gegnerWahl);
    if (e == 1) {
      _spielstand.siege++;
    } else if (e == -1) {
      _spielstand.niederlagen++;
    } else {
      _spielstand.unentschieden++;
    }
    _speichereSpielstand();

    // Nach 3 Sekunden eigenen Zug löschen → nächste Runde
    _aufdeckTimer?.cancel();
    _aufdeckTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _gameRef.child('choices/$_myId').remove();
    });
  }

  // ─── Navigation ─────────────────────────────────────────────────────────

  Future<void> _neuSuchen() async {
    _gameSub?.cancel();
    _aufdeckTimer?.cancel();
    _gameId = '';
    _gegnerId = '';
    _gegnerName = '';
    _meineWahl = null;
    _gegnerWahl = null;
    _gameStarted = false;
    await _startSearch();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // Cleanup wird in dispose() erledigt
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('✂️🪨✋ Schere Stein Papier'),
          actions: [
            if (_phase == _Phase.waehle ||
                _phase == _Phase.bestaetigt ||
                _phase == _Phase.aufdecken)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Spielstand zurücksetzen',
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Spielstand zurücksetzen?'),
                    content: Text(
                        'Nur der Spielstand gegen $_gegnerName wird gelöscht.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Abbrechen')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _spielstandZuruecksetzen();
                        },
                        child: const Text('Zurücksetzen'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() => switch (_phase) {
        _Phase.suche => _buildLaden('Suche Gegner...'),
        _Phase.warte => _buildWarte(),
        _Phase.waehle || _Phase.bestaetigt || _Phase.aufdecken => _buildSpiel(),
        _Phase.gegnerWeg => _buildGegnerWeg(),
      };

  Widget _buildLaden(String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, style: const TextStyle(fontSize: 18)),
          ],
        ),
      );

  Widget _buildWarte() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Warte auf Gegner...', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      );

  Widget _buildSpiel() => Column(
        children: [
          _buildSpielstandKarte(),
          const Spacer(),
          if (_phase == _Phase.aufdecken)
            _buildAufdecken()
          else
            _buildWahlBereich(),
          const Spacer(),
        ],
      );

  Widget _buildSpielstandKarte() => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpielstandSpalte(_myName, _spielstand.siege, Colors.green),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(':', style: TextStyle(fontSize: 32, color: Colors.grey)),
              ),
              _buildSpielstandSpalte(
                  _gegnerName, _spielstand.niederlagen, Colors.red),
              if (_spielstand.unentschieden > 0) ...[
                const SizedBox(width: 16),
                _buildSpielstandSpalte(
                    'U', _spielstand.unentschieden, Colors.grey),
              ],
            ],
          ),
        ),
      );

  Widget _buildSpielstandSpalte(String label, int wert, Color farbe) => Column(
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          Text('$wert',
              style: TextStyle(fontSize: 32, color: farbe, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _buildWahlBereich() => Column(
        children: [
          if (_phase == _Phase.bestaetigt)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                'Warte auf $_gegnerName...',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _Zug.values.map(_buildZugButton).toList(),
          ),
          const SizedBox(height: 28),
          if (_phase == _Phase.waehle && _meineWahl != null)
            ElevatedButton(
              onPressed: _wahlBestaetigen,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              ),
              child: const Text('Bestätigen ✓', style: TextStyle(fontSize: 18)),
            ),
        ],
      );

  Widget _buildZugButton(_Zug zug) {
    final ausgewaehlt = _meineWahl == zug;
    final gesperrt = _phase == _Phase.bestaetigt;
    return GestureDetector(
      onTap: gesperrt ? null : () => setState(() => _meineWahl = zug),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ausgewaehlt
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade200,
          border: Border.all(
            color: ausgewaehlt
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            _zugEmoji[zug]!,
            style: TextStyle(fontSize: gesperrt ? 30 : 36),
          ),
        ),
      ),
    );
  }

  Widget _buildAufdecken() {
    final e = _ergebnis(_meineWahl!, _gegnerWahl!);
    final (text, farbe) = switch (e) {
      1 => ('Gewonnen! 🎉', Colors.green),
      -1 => ('Verloren! 😞', Colors.red),
      _ => ('Unentschieden! 🤝', Colors.orange),
    };

    return Column(
      children: [
        Text(text,
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: farbe)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAufdeckSpalte(_myName, _meineWahl!),
            const Text('vs', style: TextStyle(fontSize: 22, color: Colors.grey)),
            _buildAufdeckSpalte(_gegnerName, _gegnerWahl!),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Nächste Runde startet gleich...',
            style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildAufdeckSpalte(String name, _Zug zug) => Column(
        children: [
          Text(name,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(_zugEmoji[zug]!, style: const TextStyle(fontSize: 60)),
        ],
      );

  Widget _buildGegnerWeg() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '$_gegnerName hat das Spiel verlassen.',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _neuSuchen,
              child: const Text('Neu suchen'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Beenden'),
            ),
          ],
        ),
      );
}
