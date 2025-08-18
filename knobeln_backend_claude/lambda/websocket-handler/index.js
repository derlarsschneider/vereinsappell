// lambda/websocket-handler/index.js
const AWS = require('aws-sdk');

const dynamoDB = new AWS.DynamoDB.DocumentClient();

const GAMES_TABLE = process.env.GAMES_TABLE_NAME;
const CONNECTIONS_TABLE = process.env.CONNECTIONS_TABLE_NAME;

// Verbindung hinzufügen
const handleConnect = async (event) => {
  const connectionId = event.requestContext.connectionId;
  const { gameId } = event.queryStringParameters || {};

  console.log('WebSocket Connect:', { connectionId, gameId });

  if (!gameId) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'gameId query parameter is required' })
    };
  }

  try {
    // Prüfen ob das Spiel existiert
    const gameResult = await dynamoDB.get({
      TableName: GAMES_TABLE,
      Key: { gameId }
    }).promise();

    if (!gameResult.Item) {
      return {
        statusCode: 404,
        body: JSON.stringify({ error: 'Game not found' })
      };
    }

    // Verbindung in der Datenbank speichern
    const connectionData = {
      connectionId,
      gameId,
      connectedAt: new Date().toISOString(),
      ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 Stunden TTL
    };

    await dynamoDB.put({
      TableName: CONNECTIONS_TABLE,
      Item: connectionData
    }).promise();

    console.log('WebSocket connection stored:', connectionData);

    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Connected successfully' })
    };
  } catch (error) {
    console.error('Error handling connect:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Could not connect' })
    };
  }
};

// Verbindung trennen
const handleDisconnect = async (event) => {
  const connectionId = event.requestContext.connectionId;

  console.log('WebSocket Disconnect:', { connectionId });

  try {
    // Verbindung aus der Datenbank entfernen
    await dynamoDB.delete({
      TableName: CONNECTIONS_TABLE,
      Key: { connectionId }
    }).promise();

    console.log('WebSocket connection removed:', connectionId);

    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Disconnected successfully' })
    };
  } catch (error) {
    console.error('Error handling disconnect:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Could not disconnect' })
    };
  }
};

// Standard-Route (für Nachrichten)
const handleDefault = async (event) => {
  const connectionId = event.requestContext.connectionId;

  console.log('WebSocket Default route:', { connectionId, body: event.body });

  try {
    // Hier können später spezifische WebSocket-Nachrichten verarbeitet werden
    // Für jetzt nur ein Ping-Pong implementieren
    const body = JSON.parse(event.body || '{}');

    if (body.action === 'ping') {
      const apiGateway = new AWS.ApiGatewayManagementApi({
        endpoint: `https://${event.requestContext.domainName}/${event.requestContext.stage}`
      });

      await apiGateway.postToConnection({
        ConnectionId: connectionId,
        Data: JSON.stringify({
          type: 'PONG',
          timestamp: new Date().toISOString()
        })
      }).promise();
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Message processed' })
    };
  } catch (error) {
    console.error('Error handling default route:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Could not process message' })
    };
  }
};

// Haupthandler
exports.handler = async (event) => {
  console.log('WebSocket Event:', JSON.stringify(event, null, 2));

  const { routeKey } = event.requestContext;

  try {
    switch (routeKey) {
      case '$connect':
        return await handleConnect(event);
      case '$disconnect':
        return await handleDisconnect(event);
      case '$default':
        return await handleDefault(event);
      default:
        console.log('Unknown route:', routeKey);
        return {
          statusCode: 400,
          body: JSON.stringify({ error: 'Unknown route' })
        };
    }
  } catch (error) {
    console.error('Unhandled WebSocket error:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Internal server error' })
    };
  }
};
