// knobeln_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:provider/provider.dart';

// --- Konfiguration ---
// Ersetze diese URLs mit den Outputs deines Terraform-Deployments
const String HTTP_API_URL = 'https://<deine-http-api-id>.execute-api.eu-central-1.amazonaws.com/prod';
const String WS_API_URL = 'wss://<deine-ws-api-id>.execute-api.eu-central-1.amazonaws.com/prod';

// --- Datenmodelle ---
class Player {
  final String id;
  final String name;
  final bool isEliminated;
  final int? pickedSticks;
  final int? guess;

  Player({
    required this.id,
    required this.name,
    this.isEliminated = false,
    this.pickedSticks,
    this.guess,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'],
      name: json['name'],
      isEliminated: json['isEliminated'],
      pickedSticks: json['pickedSticks'],
      guess: json['guess'],
    );
  }
}

class GameState {
  final String gameId;
  final String status;
  final String currentPhase;
  final int roundNumber;
  final int turnPlayerIndex;
  final List<Player> players;
  final String? loserId;

  GameState({
    required this.gameId,
    required this.status,
    required this.currentPhase,
    required this.roundNumber,
    required this.turnPlayerIndex,
    required this.players,
    this.loserId,
  });

  factory GameState.fromJson(Map<String, dynamic> json) {
    var playersList = json['players'] as List;
    List<Player> players = playersList.map((i) => Player.fromJson(i)).toList();
    return GameState(
      gameId: json['gameId'],
      status: json['status'],
      currentPhase: json['currentPhase'],
      roundNumber: json['roundNumber'],
      turnPlayerIndex: json['turnPlayerIndex'],
      players: players,
      loserId: json['loserId'],
    );
  }
}

// --- State Management mit Provider ---
class GameProvider extends ChangeNotifier {
  GameState? _gameState;
  WebSocketChannel? _channel;
  bool _isLoading = false;
  String? _error;

  // Annahme: Die ID des aktuellen Spielers ist bekannt
  String currentPlayerId = "user123";
  String currentPlayerName = "Lars";

  GameState? get gameState => _gameState;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _setGameState(GameState newState) {
    _gameState = newState;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createGame() async {
    _setLoading(true);
    try {
      final response = await http.post(
        Uri.parse('$HTTP_API_URL/games'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': currentPlayerId, 'playerName': currentPlayerName}),
      );
      if (response.statusCode == 201) {
        final newGameState = GameState.fromJson(jsonDecode(response.body));
        _setGameState(newGameState);
        _connectToWebSocket(newGameState.gameId);
      } else {
        _setError('Fehler beim Erstellen des Spiels: ${response.body}');
      }
    } catch (e) {
      _setError('Netzwerkfehler: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> joinGame(String gameId) async {
    _setLoading(true);
    try {
      final response = await http.post(
        Uri.parse('$HTTP_API_URL/games/$gameId/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': currentPlayerId, 'playerName': currentPlayerName}),
      );
      if (response.statusCode == 200) {
        final newGameState = GameState.fromJson(jsonDecode(response.body));
        _setGameState(newGameState);
        _connectToWebSocket(newGameState.gameId);
      } else {
        _setError('Fehler beim Beitreten: ${response.body}');
      }
    } catch (e) {
      _setError('Netzwerkfehler: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> pickSticks(int sticks) async {
    if (_gameState == null) return;
    _setLoading(true);
    try {
      await http.post(
        Uri.parse('$HTTP_API_URL/games/${_gameState!.gameId}/pick'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': currentPlayerId, 'sticks': sticks}),
      );
    } catch (e) {
      _setError('Fehler beim Wählen der Hölzer: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> guess(int guess) async {
    if (_gameState == null) return;
    _setLoading(true);
    try {
      final response = await http.post(
        Uri.parse('$HTTP_API_URL/games/${_gameState!.gameId}/guess'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': currentPlayerId, 'guess': guess}),
      );
      if (response.statusCode != 200) {
        _setError(jsonDecode(response.body)['message']);
      }
    } catch (e) {
      _setError('Fehler beim Raten: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _connectToWebSocket(String gameId) {
    _channel?.sink.close(); // Schließe alte Verbindung
    _channel = WebSocketChannel.connect(Uri.parse('$WS_API_URL?gameId=$gameId'));
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'game_update' || data['type'] == 'game_started') {
        final newGameState = GameState.fromJson(data['game']);
        _setGameState(newGameState);
      }
    }, onError: (error) {
      _setError("WebSocket Fehler: $error");
      _channel = null;
    }, onDone: () {
      _channel = null;
    });
  }

  void leaveGame() {
    _channel?.sink.close();
    _gameState = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}

// --- UI Widgets ---
class KnobelnScreen extends StatelessWidget {
  const KnobelnScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameProvider(),
      child: Consumer<GameProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            appBar: AppBar(title: const Text('Knobeln')),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildContent(context, provider),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, GameProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return Center(child: Text('Fehler: ${provider.error}', style: const TextStyle(color: Colors.red)));
    }
    if (provider.gameState == null) {
      return const LobbyWidget();
    }
    return GameWidget(gameState: provider.gameState!);
  }
}

class LobbyWidget extends StatelessWidget {
  const LobbyWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final gameIdController = TextEditingController();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () => context.read<GameProvider>().createGame(),
            child: const Text('Neues Spiel erstellen'),
          ),
          const SizedBox(height: 20),
          const Text('ODER'),
          const SizedBox(height: 20),
          TextField(
            controller: gameIdController,
            decoration: const InputDecoration(
              labelText: 'Game ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {
              if (gameIdController.text.isNotEmpty) {
                context.read<GameProvider>().joinGame(gameIdController.text);
              }
            },
            child: const Text('Spiel beitreten'),
          ),
        ],
      ),
    );
  }
}

class GameWidget extends StatelessWidget {
  final GameState gameState;
  const GameWidget({Key? key, required this.gameState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GameProvider>();
    final me = gameState.players.firstWhere((p) => p.id == provider.currentPlayerId, orElse: () => Player(id: '', name: ''));

    return ListView(
      children: [
        Text('Game ID: ${gameState.gameId}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Text('Status: ${gameState.status}', style: Theme.of(context).textTheme.headlineSmall),
        Text('Phase: ${gameState.currentPhase}', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        if (gameState.status == 'finished') _buildFinishedView(context),
        if (gameState.status == 'running' && gameState.currentPhase == 'pick' && !me.isEliminated)
          PickSticksWidget(),
        if (gameState.status == 'running' && gameState.currentPhase == 'guess' && !me.isEliminated)
          GuessWidget(),
        const SizedBox(height: 20),
        PlayerList(players: gameState.players),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () => provider.leaveGame(),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Spiel verlassen'),
        )
      ],
    );
  }

  Widget _buildFinishedView(BuildContext context) {
    final loser = gameState.players.firstWhere((p) => p.id == gameState.loserId, orElse: () => Player(id: '', name: 'Niemand'));
    return Card(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'Spiel beendet! ${loser.name} hat verloren!',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PlayerList extends StatelessWidget {
  final List<Player> players;
  const PlayerList({Key? key, required this.players}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spieler:', style: Theme.of(context).textTheme.titleLarge),
        ...players.map((p) => ListTile(
          leading: Icon(p.isEliminated ? Icons.close : Icons.check, color: p.isEliminated ? Colors.red : Colors.green),
          title: Text(p.name),
          subtitle: Text('ID: ${p.id}'),
        )),
      ],
    );
  }
}

class PickSticksWidget extends StatelessWidget {
  const PickSticksWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Wähle deine Hölzer', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [0, 1, 2, 3].map((n) => ElevatedButton(
                onPressed: () => context.read<GameProvider>().pickSticks(n),
                child: Text('$n'),
              )).toList(),
            )
          ],
        ),
      ),
    );
  }
}

class GuessWidget extends StatelessWidget {
  const GuessWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final guessController = TextEditingController();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Gib deine Schätzung ab', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextField(
              controller: guessController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Gesamtanzahl Hölzer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                final guess = int.tryParse(guessController.text);
                if (guess != null) {
                  context.read<GameProvider>().guess(guess);
                }
              },
              child: const Text('Raten'),
            )
          ],
        ),
      ),
    );
  }
}
