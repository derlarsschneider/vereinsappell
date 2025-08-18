// lambda/game-timer/index.js
const AWS = require('aws-sdk');

const dynamoDB = new AWS.DynamoDB.DocumentClient();
const apiGateway = new AWS.ApiGatewayManagementApi({
  endpoint: process.env.WEBSOCKET_API_ENDPOINT
});

const GAMES_TABLE = process.env.GAMES_TABLE_NAME;
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE_NAME;

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

// Timer für nächstes Event setzen
const scheduleGameEvent = async (gameId, eventType, delaySeconds, payload = {}) => {
  const scheduler = new AWS.EventBridgeScheduler();
  const scheduleName = `${gameId}-${eventType}-${Date.now()}`;
  const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

  const scheduleInput = {
    Name: scheduleName,
    ScheduleExpression: `at(${scheduleTime.toISOString().slice(0, 19)})`,
    Target: {
      Arn: process.env.AWS_LAMBDA_FUNCTION_NAME, // Verweis auf sich selbst
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
  } catch (error) {
    console.error('Error scheduling event:', error);
  }
};

// Spiel starten (nach 60 Sekunden Wartezeit)
const handleStartGame = async (gameId) => {
  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      console.log('Game not found:', gameId);
      return;
    }

    const game = gameResult.Item;

    if (game.status !== 'waiting') {
      console.log('Game is not in waiting state:', game.status);
      return;
    }

    // Spiel auf "running" setzen und erste Runde starten
    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET #status = :status, currentPhase = :phase, roundNumber = :round',
      ExpressionAttributeNames: {
        '#status': 'status'
      },
      ExpressionAttributeValues: {
        ':status': 'running',
        ':phase': 'pick',
        ':round': 1
      }
    }).promise();

    // Timer für automatische Hölzerwahl setzen (30 Sekunden)
    await scheduleGameEvent(gameId, 'AUTO_PICK', 30);

    // Aktualisiertes Spiel laden
    const updatedGameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    // Alle Spieler benachrichtigen
    await broadcastToGame(gameId, {
      type: 'GAME_STARTED',
      game: updatedGameResult.Item
    });

    console.log('Game started:', gameId);
  } catch (error) {
    console.error('Error starting game:', error);
  }
};

// Automatische Hölzerwahl (nach 30 Sekunden Timeout)
const handleAutoPick = async (gameId) => {
  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      console.log('Game not found:', gameId);
      return;
    }

    const game = gameResult.Item;

    if (game.status !== 'running' || game.currentPhase !== 'pick') {
      console.log('Game is not in picking phase:', game.status, game.currentPhase);
      return;
    }

    // Alle aktiven Spieler, die noch nicht gewählt haben, auf 3 Hölzer setzen
    const updatedPlayers = game.players.map(player => {
      if (!player.isEliminated && player.pickedSticks === null) {
        return { ...player, pickedSticks: 3 };
      }
      return player;
    });

    const activePlayers = updatedPlayers.filter(p => !p.isEliminated);
    const totalSticks = activePlayers.reduce((sum, p) => sum + p.pickedSticks, 0);

    // Zur Schätzphase wechseln
    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET players = :players, currentPhase = :phase, totalSticks = :total, guesses = :empty',
      ExpressionAttributeValues: {
        ':players': updatedPlayers,
        ':phase': 'guess',
        ':total': totalSticks,
        ':empty': []
      }
    }).promise();

    // Aktualisiertes Spiel laden
    const updatedGameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    // Alle Spieler benachrichtigen
    await broadcastToGame(gameId, {
      type: 'AUTO_PICK_EXECUTED',
      game: updatedGameResult.Item,
      message: 'Time expired - automatically set to 3 sticks for players who haven\'t picked'
    });

    console.log('Auto-pick executed for game:', gameId);
  } catch (error) {
    console.error('Error executing auto-pick:', error);
  }
};

// Automatische Schätzung (Fallback, falls benötigt)
const handleAutoGuess = async (gameId) => {
  try {
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      console.log('Game not found:', gameId);
      return;
    }

    const game = gameResult.Item;

    if (game.status !== 'running' || game.currentPhase !== 'guess') {
      console.log('Game is not in guessing phase:', game.status, game.currentPhase);
      return;
    }

    const activePlayers = game.players.filter(p => !p.isEliminated);
    const currentGuesses = game.guesses || [];

    // Spieler finden, die noch nicht geraten haben
    const playersWhoHaventGuessed = activePlayers.filter(
      player => !currentGuesses.some(guess => guess.playerId === player.playerId)
    );

    if (playersWhoHaventGuessed.length === 0) {
      console.log('All players have already guessed');
      return;
    }

    // Für jeden Spieler, der noch nicht geraten hat, eine zufällige Schätzung abgeben
    const newGuesses = [...currentGuesses];

    playersWhoHaventGuessed.forEach(player => {
      // Zufällige Schätzung zwischen 0 und totalSticks + 2
      const randomGuess = Math.floor(Math.random() * (game.totalSticks + 3));

      newGuesses.push({
        playerId: player.playerId,
        playerName: player.playerName,
        guess: randomGuess,
        timestamp: new Date().toISOString(),
        isAutoGuess: true
      });
    });

    await dynamoDB.update({
      TableName: GAMES_TABLE,
      Key: { gameId },
      UpdateExpression: 'SET guesses = :guesses',
      ExpressionAttributeValues: {
        ':guesses': newGuesses
      }
    }).promise();

    // Runde abschließen
    await processRoundEnd(gameId, game, newGuesses);

    console.log('Auto-guess executed for game:', gameId);
  } catch (error) {
    console.error('Error executing auto-guess:', error);
  }
};

// Runde abschließen (kopiert von game-handler)
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
  }
};

// Haupthandler
exports.handler = async (event) => {
  console.log('Timer Event:', JSON.stringify(event, null, 2));

  const { gameId, eventType } = event;

  if (!gameId || !eventType) {
    console.error('Missing gameId or eventType in event');
    return;
  }

  try {
    switch (eventType) {
      case 'START_GAME':
        await handleStartGame(gameId);
        break;
      case 'AUTO_PICK':
        await handleAutoPick(gameId);
        break;
      case 'AUTO_GUESS':
        await handleAutoGuess(gameId);
        break;
      default:
        console.log('Unknown event type:', eventType);
    }
  } catch (error) {
    console.error('Error processing timer event:', error);
  }
};
