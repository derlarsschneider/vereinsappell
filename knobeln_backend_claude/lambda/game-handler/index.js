// lambda/game-handler/index.js
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const dynamoDB = new AWS.DynamoDB.DocumentClient();
const apiGateway = new AWS.ApiGatewayManagementApi({
  endpoint: process.env.WEBSOCKET_API_ENDPOINT
});
const eventBridge = new AWS.EventBridge();
const scheduler = new AWS.EventBridgeScheduler();

const GAMES_TABLE = process.env.GAMES_TABLE_NAME;
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE_NAME;
const TIMER_LAMBDA_ARN = process.env.TIMER_LAMBDA_ARN;

// Hilfsfunktionen
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
};

const response = (statusCode, body) => ({
  statusCode,
  headers: corsHeaders,
  body: JSON.stringify(body)
});

// WebSocket-Nachrichten an alle Spieler senden
const broadcastToGame = async (gameId, message) => {
  try {
    const connections = await dynamoDB.query({
      TableName: CONNECTIONS_TABLE,
      IndexName: 'GameIdIndex',
      KeyConditionExpression: 'gameId = :gameId',
      ExpressionAttributeValues: {
        ':gameId': gameId
      }
    }).promise();

    const promises = connections.Items.map(async (connection) => {
      try {
        await apiGateway.postToConnection({
          ConnectionId: connection.connectionId,
          Data: JSON.stringify(message)
        }).promise();
      } catch (error) {
        if (error.statusCode === 410) {
          // Verbindung ist tot, aus der Tabelle entfernen
          await dynamoDB.delete({
            TableName: CONNECTIONS_TABLE,
            Key: { connectionId: connection.connectionId }
          }).promise();
        }
      }
    });

    await Promise.all(promises);
  } catch (error) {
    console.error('Error broadcasting to game:', error);
  }
};

// Timer für EventBridge Scheduler erstellen
const scheduleGameEvent = async (gameId, eventType, delaySeconds, payload = {}) => {
  const scheduleName = `${gameId}-${eventType}-${Date.now()}`;
  const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

  const scheduleInput = {
    Name: scheduleName,
    ScheduleExpression: `at(${scheduleTime.toISOString().slice(0, 19)})`,
    Target: {
      Arn: TIMER_LAMBDA_ARN,
      RoleArn: process.env.SCHEDULER_ROLE_ARN,
      Input: JSON.stringify({
        gameId,
        eventType,
        ...payload
      })
    },
    FlexibleTimeWindow: {
      Mode: 'OFF'
    }
  };

  try {
    await scheduler.createSchedule(scheduleInput).promise();
    console.log(`Scheduled ${eventType} for game ${gameId} in ${delaySeconds} seconds`);

    // Schedule-Name in der Spiel-Datenbank speichern für späteren Cleanup
    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET scheduledEvents = list_append(if_not_exists(scheduledEvents, :empty), :event)',
      ExpressionAttributeValues: {
        ':empty': [],
        ':event': [scheduleName]
      }
    }).promise();

  } catch (error) {
    console.error('Error scheduling event:', error);
    throw error;
  }
};

// Spiel erstellen
const createGame = async (event) => {
  const body = JSON.parse(event.body || '{}');
  const { playerId, playerName } = body;

  if (!playerId || !playerName) {
    return response(400, { error: 'playerId and playerName are required' });
  }

  const gameId = uuidv4();
  const now = new Date().toISOString();
  const gameStartTime = new Date(Date.now() + 60000).toISOString(); // 60 Sekunden

  const gameData = {
    gameId,
    status: 'waiting',
    createdAt: now,
    gameStartTime,
    players: [{
      playerId,
      playerName,
      joinedAt: now,
      pickedSticks: null,
      guess: null,
      isEliminated: false
    }],
    currentPhase: null,
    roundNumber: 0,
    turnPlayerIndex: 0,
    totalSticks: 0,
    guesses: [],
    ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 Stunden TTL
  };

  try {
    await dynamoDB.put({
      TableName: GAMES_TABLE,
      Item: gameData
    }).promise();

    // Timer für Spielstart setzen
    await scheduleGameEvent(gameId, 'START_GAME', 60);

    return response(201, { gameId, game: gameData });
  } catch (error) {
    console.error('Error creating game:', error);
    return response(500, { error: 'Could not create game' });
  }
};

// Spiel beitreten
const joinGame = async (event) => {
  const { gameId } = event.pathParameters;
  const body = JSON.parse(event.body || '{}');
  const { playerId, playerName } = body;

  if (!playerId || !playerName) {
    return response(400, { error: 'playerId and playerName are required' });
  }

  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      return response(404, { error: 'Game not found' });
    }

    const game = gameResult.Item;

    if (game.status !== 'waiting') {
      return response(400, { error: 'Game is not accepting new players' });
    }

    // Prüfen ob Spieler bereits im Spiel ist
    if (game.players.some(p => p.playerId === playerId)) {
      return response(400, { error: 'Player already in game' });
    }

    const newPlayer = {
      playerId,
      playerName,
      joinedAt: new Date().toISOString(),
      pickedSticks: null,
      guess: null,
      isEliminated: false
    };

    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET players = list_append(players, :player)',
      ExpressionAttributeValues: {
        ':player': [newPlayer]
      }
    }).promise();

    // Aktualisiertes Spiel laden
    const updatedGameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    // WebSocket-Nachricht an alle Spieler
    await broadcastToGame(gameId, {
      type: 'PLAYER_JOINED',
      game: updatedGameResult.Item
    });

    return response(200, { game: updatedGameResult.Item });
  } catch (error) {
    console.error('Error joining game:', error);
    return response(500, { error: 'Could not join game' });
  }
};

// Hölzer wählen
const pickSticks = async (event) => {
  const { gameId } = event.pathParameters;
  const body = JSON.parse(event.body || '{}');
  const { playerId, sticksCount } = body;

  if (!playerId || sticksCount === undefined || sticksCount < 0 || sticksCount > 3) {
    return response(400, { error: 'Valid playerId and sticksCount (0-3) are required' });
  }

  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      return response(404, { error: 'Game not found' });
    }

    const game = gameResult.Item;

    if (game.status !== 'running' || game.currentPhase !== 'pick') {
      return response(400, { error: 'Game is not in picking phase' });
    }

    const playerIndex = game.players.findIndex(p => p.playerId === playerId);
    if (playerIndex === -1) {
      return response(400, { error: 'Player not in game' });
    }

    if (game.players[playerIndex].isEliminated) {
      return response(400, { error: 'Player is eliminated' });
    }

    // Spieler-Auswahl aktualisieren
    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET players[' + playerIndex + '].pickedSticks = :sticks',
      ExpressionAttributeValues: {
        ':sticks': sticksCount
      }
    }).promise();

    // Spiel neu laden
    const updatedGameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();
    const updatedGame = updatedGameResult.Item;

    // Prüfen ob alle aktiven Spieler gewählt haben
    const activePlayers = updatedGame.players.filter(p => !p.isEliminated);
    const allPicked = activePlayers.every(p => p.pickedSticks !== null);

    if (allPicked) {
      // Zur Schätzphase wechseln
      const totalSticks = activePlayers.reduce((sum, p) => sum + p.pickedSticks, 0);

      await dynamoDB.update({
        TableName: GAMES_TABLE,
        Key: { gameId },
        UpdateExpression: 'SET currentPhase = :phase, totalSticks = :total, guesses = :empty',
        ExpressionAttributeValues: {
          ':phase': 'guess',
          ':total': totalSticks,
          ':empty': []
        }
      }).promise();

      const finalGameResult = await dynamoDB.get({
        TableName: GAMES_TABLE,
        Key: { gameId }
      }).promise();

      await broadcastToGame(gameId, {
        type: 'PHASE_CHANGED',
        game: finalGameResult.Item
      });
    } else {
      await broadcastToGame(gameId, {
        type: 'PLAYER_PICKED',
        game: updatedGame
      });
    }

    return response(200, { game: updatedGame });
  } catch (error) {
    console.error('Error picking sticks:', error);
    return response(500, { error: 'Could not pick sticks' });
  }
};

// Schätzung abgeben
const makeGuess = async (event) => {
  const { gameId } = event.pathParameters;
  const body = JSON.parse(event.body || '{}');
  const { playerId, guessCount } = body;

  if (!playerId || guessCount === undefined || guessCount < 0) {
    return response(400, { error: 'Valid playerId and guessCount are required' });
  }

  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      return response(404, { error: 'Game not found' });
    }

    const game = gameResult.Item;

    if (game.status !== 'running' || game.currentPhase !== 'guess') {
      return response(400, { error: 'Game is not in guessing phase' });
    }

    const player = game.players.find(p => p.playerId === playerId);
    if (!player) {
      return response(400, { error: 'Player not in game' });
    }

    if (player.isEliminated) {
      return response(400, { error: 'Player is eliminated' });
    }

    // Prüfen ob Spieler bereits geraten hat
    if (game.guesses.some(g => g.playerId === playerId)) {
      return response(400, { error: 'Player has already guessed' });
    }

    const activePlayers = game.players.filter(p => !p.isEliminated);
    const currentGuesses = [...game.guesses];

    // Prüfung: Letzter Spieler darf nicht die gleiche Zahl wie alle anderen wählen
    if (currentGuesses.length === activePlayers.length - 1) {
      const existingGuesses = currentGuesses.map(g => g.guess);
      const allSameGuess = existingGuesses.every(g => g === existingGuesses[0]);

      if (allSameGuess && guessCount === existingGuesses[0]) {
        return response(400, {
          error: 'Last player cannot guess the same number as all others',
          suggestedGuesses: Array.from({length: Math.max(10, game.totalSticks + 3)}, (_, i) => i).filter(i => i !== existingGuesses[0])
        });
      }
    }

    const newGuess = {
      playerId,
      playerName: player.playerName,
      guess: guessCount,
      timestamp: new Date().toISOString()
    };

    currentGuesses.push(newGuess);

    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET guesses = :guesses',
      ExpressionAttributeValues: {
        ':guesses': currentGuesses
      }
    }).promise();

    // Prüfen ob alle aktiven Spieler geraten haben
    if (currentGuesses.length === activePlayers.length) {
      await processRoundEnd(gameId, game, currentGuesses);
    } else {
      // Spiel neu laden und broadcast
      const updatedGameResult = await dynamoDB.get({
        TableName: GAMES_TABLE,
        Key: { gameId }
      }).promise();

      await broadcastToGame(gameId, {
        type: 'PLAYER_GUESSED',
        game: updatedGameResult.Item
      });
    }

    const finalGameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    return response(200, { game: finalGameResult.Item });
  } catch (error) {
    console.error('Error making guess:', error);
    return response(500, { error: 'Could not make guess' });
  }
};

// Runde abschließen und Gewinner ermitteln
const processRoundEnd = async (gameId, game, guesses) => {
  try {
    const correctGuess = game.totalSticks;
    const winners = guesses.filter(g => g.guess === correctGuess);

    // Gewinner eliminieren (sie sind raus)
    const updatedPlayers = game.players.map(player => {
      if (winners.some(w => w.playerId === player.playerId)) {
        return { ...player, isEliminated: true };
      }
      return player;
    });

    const remainingPlayers = updatedPlayers.filter(p => !p.isEliminated);

    if (remainingPlayers.length === 1) {
      // Spiel beendet - letzter Spieler hat verloren
      await dynamoDB.update({
        TableName: GAMES_TABLE,
        Key: { gameId },
        UpdateExpression: 'SET #status = :status, players = :players, loserId = :loserId, finishedAt = :finishedAt',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':status': 'finished',
          ':players': updatedPlayers,
          ':loserId': remainingPlayers[0].playerId,
          ':finishedAt': new Date().toISOString()
        }
      }).promise();

      const finishedGame = await dynamoDB.get({
        TableName: GAMES_TABLE,
        Key: { gameId }
      }).promise();

      await broadcastToGame(gameId, {
        type: 'GAME_FINISHED',
        game: finishedGame.Item,
        winners: winners,
        loser: remainingPlayers[0]
      });
    } else {
      // Nächste Runde starten
      const nextRound = game.roundNumber + 1;
      const nextTurnPlayerIndex = (game.turnPlayerIndex + 1) % game.players.length;

      // Spieler-Daten für neue Runde zurücksetzen
      const resetPlayers = updatedPlayers.map(player => ({
        ...player,
        pickedSticks: null,
        guess: null
      }));

      await dynamoDB.update({
        TableName: GAMES_TABLE,
        Key: { gameId },
        UpdateExpression: 'SET currentPhase = :phase, roundNumber = :round, turnPlayerIndex = :turnIndex, players = :players, guesses = :empty, totalSticks = :zero',
        ExpressionAttributeValues: {
          ':phase': 'pick',
          ':round': nextRound,
          ':turnIndex': nextTurnPlayerIndex,
          ':players': resetPlayers,
          ':empty': [],
          ':zero': 0
        }
      }).promise();

      // Timer für automatische Hölzerwahl setzen (30 Sekunden)
      await scheduleGameEvent(gameId, 'AUTO_PICK', 30);

      const nextRoundGame = await dynamoDB.get({
        TableName: GAMES_TABLE,
        Key: { gameId }
      }).promise();

      await broadcastToGame(gameId, {
        type: 'ROUND_ENDED',
        game: nextRoundGame.Item,
        roundWinners: winners,
        correctGuess: correctGuess
      });
    }
  } catch (error) {
    console.error('Error processing round end:', error);
    throw error;
  }
};

// Spiel abrufen
const getGame = async (event) => {
  const { gameId } = event.pathParameters;

  try {
    const result = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!result.Item) {
      return response(404, { error: 'Game not found' });
    }

    return response(200, { game: result.Item });
  } catch (error) {
    console.error('Error getting game:', error);
    return response(500, { error: 'Could not get game' });
  }
};

// Haupthandler
exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const { httpMethod, path } = event;
  const route = `${httpMethod} ${path}`;

  try {
    switch (route) {
      case 'POST /games':
        return await createGame(event);
      case 'GET /games/{gameId}':
        return await getGame(event);
      default:
        // Dynamische Routen basierend auf dem Pfad
        if (event.pathParameters && event.pathParameters.gameId) {
          if (httpMethod === 'POST' && path.endsWith('/join')) {
            return await joinGame(event);
          } else if (httpMethod === 'POST' && path.endsWith('/pick')) {
            return await pickSticks(event);
          } else if (httpMethod === 'POST' && path.endsWith('/guess')) {
            return await makeGuess(event);
          }
        }
        return response(404, { error: 'Route not found' });
    }
  } catch (error) {
    console.error('Unhandled error:', error);
    return response(500, { error: 'Internal server error' });
  }
};
