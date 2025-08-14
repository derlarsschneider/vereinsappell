# lambda/game_logic/main.py
import json
import boto3
import os
import time
import uuid
from decimal import Decimal

# Initialisiere AWS Clients
dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')
apigatewaymanagementapi = boto3.client('apigatewaymanagementapi', endpoint_url=os.environ.get('WS_API_ENDPOINT'))

# Hole Tabellennamen aus Umgebungsvariablen
GAMES_TABLE_NAME = os.environ.get('GAMES_TABLE_NAME')
CONNECTIONS_TABLE_NAME = os.environ.get('CONNECTIONS_TABLE_NAME')
PROJECT_NAME = os.environ.get('PROJECT_NAME')

games_table = dynamodb.Table(GAMES_TABLE_NAME)
connections_table = dynamodb.Table(CONNECTIONS_TABLE_NAME)

# --- Hilfsfunktionen ---
def default_serializer(obj):
    """JSON-Serializer für Objekte, die nicht standardmäßig serialisierbar sind."""
    if isinstance(obj, Decimal):
        return int(obj)
    raise TypeError(f"Object of type {obj.__class__.__name__} is not JSON serializable")

def send_to_all(game_id, data):
    """Sendet eine Nachricht an alle WebSocket-Clients in einem Spiel."""
    response = connections_table.query(
        IndexName='gameId-index',
        KeyConditionExpression='gameId = :gid',
        ExpressionAttributeValues={':gid': game_id}
    )
    for item in response.get('Items', []):
        try:
            apigatewaymanagementapi.post_to_connection(
                ConnectionId=item['connectionId'],
                Data=json.dumps(data, default=default_serializer)
            )
        except apigatewaymanagementapi.exceptions.GoneException:
            # Client ist nicht mehr verbunden, aus Tabelle entfernen
            connections_table.delete_item(Key={'connectionId': item['connectionId']})

def _get_game(game_id):
    """Holt den Spielstatus aus DynamoDB."""
    response = games_table.get_item(Key={'gameId': game_id})
    return response.get('Item')

# --- Haupt-Handler für HTTP-API ---
def handler(event, context):
    """Leitet Anfragen basierend auf der Route an die entsprechende Funktion weiter."""
    print(f"Received event: {json.dumps(event)}")
    route_key = event.get('routeKey')

    # EventBridge-Trigger
    if event.get('source') == 'aws.events':
        return timer_handler(event, context)

    # HTTP-API-Trigger
    path = event.get('pathParameters', {})
    game_id = path.get('gameId')
    body = json.loads(event.get('body', '{}'))

    if route_key == "POST /games":
        return create_game(body)
    elif route_key == "POST /games/{gameId}/join":
        return join_game(game_id, body)
    elif route_key == "POST /games/{gameId}/pick":
        return pick_sticks(game_id, body)
    elif route_key == "POST /games/{gameId}/guess":
        return guess_sticks(game_id, body)

    return {'statusCode': 404, 'body': json.dumps({'message': 'Not Found'})}

# --- Spiellogik-Funktionen ---

def create_game(body):
    """Erstellt ein neues Spiel."""
    game_id = str(uuid.uuid4())
    player_id = body.get('playerId')
    player_name = body.get('playerName')

    if not player_id or not player_name:
        return {'statusCode': 400, 'body': json.dumps({'message': 'playerId and playerName are required'})}

    start_time = int(time.time()) + 60

    game = {
        'gameId': game_id,
        'status': 'waiting', # waiting, running, finished
        'currentPhase': 'none', # none, pick, guess
        'roundNumber': 1,
        'turnPlayerIndex': 0,
        'players': [{
            'id': player_id,
            'name': player_name,
            'isEliminated': False,
            'pickedSticks': None,
            'guess': None
        }],
        'createdAt': int(time.time()),
        'startTime': start_time
    }

    games_table.put_item(Item=game)

    # EventBridge-Regel für den Spielstart erstellen
    rule_name = f"{PROJECT_NAME}-start-game-{game_id}"
    eventbridge.put_rule(
        Name=rule_name,
        ScheduleExpression=f"at({time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(start_time))})",
        State='ENABLED'
    )
    eventbridge.put_targets(
        Rule=rule_name,
        Targets=[{
            'Id': f"target-{game_id}",
            'Arn': context.function_arn,
            'Input': json.dumps({'action': 'startGame', 'gameId': game_id})
        }]
    )

    return {'statusCode': 201, 'body': json.dumps(game, default=default_serializer)}

def join_game(game_id, body):
    """Fügt einen Spieler zu einem wartenden Spiel hinzu."""
    player_id = body.get('playerId')
    player_name = body.get('playerName')

    if not player_id or not player_name:
        return {'statusCode': 400, 'body': json.dumps({'message': 'playerId and playerName are required'})}

    game = _get_game(game_id)
    if not game or game['status'] != 'waiting':
        return {'statusCode': 404, 'body': json.dumps({'message': 'Game not found or already started'})}

    # Spieler hinzufügen
    new_player = {
        'id': player_id,
        'name': player_name,
        'isEliminated': False,
        'pickedSticks': None,
        'guess': None
    }

    response = games_table.update_item(
        Key={'gameId': game_id},
        UpdateExpression="SET players = list_append(players, :p)",
        ExpressionAttributeValues={':p': [new_player]},
        ReturnValues="ALL_NEW"
    )

    updated_game = response['Attributes']
    send_to_all(game_id, {'type': 'game_update', 'game': updated_game})

    return {'statusCode': 200, 'body': json.dumps(updated_game, default=default_serializer)}

def pick_sticks(game_id, body):
    """Ein Spieler wählt seine Anzahl an Hölzern."""
    player_id = body.get('playerId')
    sticks = body.get('sticks')

    if player_id is None or sticks is None or not (0 <= sticks <= 3):
        return {'statusCode': 400, 'body': json.dumps({'message': 'playerId and a valid number of sticks (0-3) are required'})}

    game = _get_game(game_id)
    if not game or game['status'] != 'running' or game['currentPhase'] != 'pick':
        return {'statusCode': 403, 'body': json.dumps({'message': 'Cannot pick sticks at this time'})}

    player_index = -1
    for i, p in enumerate(game['players']):
        if p['id'] == player_id:
            player_index = i
            break

    if player_index == -1:
        return {'statusCode': 404, 'body': json.dumps({'message': 'Player not in this game'})}

    # Update der Hölzer für den Spieler
    game['players'][player_index]['pickedSticks'] = sticks

    # Prüfen, ob alle gewählt haben
    all_picked = all(p['pickedSticks'] is not None for p in game['players'] if not p['isEliminated'])

    if all_picked:
        # Phase wechseln und Timeout-Regel löschen
        game['currentPhase'] = 'guess'
        rule_name = f"{PROJECT_NAME}-pick-timeout-{game_id}"
        try:
            eventbridge.remove_targets(Rule=rule_name, Ids=[f"target-{game_id}"])
            eventbridge.delete_rule(Name=rule_name)
        except eventbridge.exceptions.ResourceNotFoundException:
            pass # Regel wurde bereits ausgelöst oder gelöscht

    games_table.put_item(Item=game)
    send_to_all(game_id, {'type': 'game_update', 'game': game})

    return {'statusCode': 200, 'body': json.dumps({'message': 'Sticks picked successfully'})}

def guess_sticks(game_id, body):
    """Ein Spieler gibt seine Schätzung ab."""
    player_id = body.get('playerId')
    guess = body.get('guess')

    if player_id is None or guess is None:
        return {'statusCode': 400, 'body': json.dumps({'message': 'playerId and guess are required'})}

    game = _get_game(game_id)
    if not game or game['status'] != 'running' or game['currentPhase'] != 'guess':
        return {'statusCode': 403, 'body': json.dumps({'message': 'Cannot guess at this time'})}

    active_players = [p for p in game['players'] if not p['isEliminated']]
    turn_player_index_in_game = game['players'].index(active_players[game['turnPlayerIndex'] % len(active_players)])

    # Finde den Spieler und prüfe, ob er an der Reihe ist
    player_index = -1
    for i, p in enumerate(game['players']):
        if p['id'] == player_id:
            player_index = i
            break

    if player_index != turn_player_index_in_game:
        return {'statusCode': 403, 'body': json.dumps({'message': "It's not your turn to guess"})}

    # Regel: Der letzte Spieler darf nicht die gleiche Zahl raten, wenn alle anderen das Gleiche geraten haben
    other_guesses = {p['guess'] for p in active_players if p['id'] != player_id and p['guess'] is not None}
    if len(active_players) - 1 > 0 and len(other_guesses) == 1 and guess in other_guesses:
        return {'statusCode': 409, 'body': json.dumps({'message': 'You cannot guess the same number as everyone else.'})}

    game['players'][player_index]['guess'] = guess

    # Prüfen, ob alle geraten haben
    all_guessed = all(p['guess'] is not None for p in active_players)

    if all_guessed:
        # Runde auswerten
        total_sticks = sum(p['pickedSticks'] for p in active_players)

        for p in active_players:
            if p['guess'] == total_sticks:
                p['isEliminated'] = True # Spieler scheidet aus

        # Prüfen, ob das Spiel vorbei ist
        remaining_players = [p for p in game['players'] if not p['isEliminated']]
        if len(remaining_players) <= 1:
            game['status'] = 'finished'
            if remaining_players:
                game['loserId'] = remaining_players[0]['id']
            else: # Alle haben gleichzeitig richtig geraten
                game['loserId'] = None # Unentschieden
        else:
            # Nächste Runde vorbereiten
            game['roundNumber'] += 1
            game['currentPhase'] = 'pick'
            game['turnPlayerIndex'] += 1 # Nächster Spieler beginnt
            # Reset für die neue Runde
            for p in game['players']:
                p['pickedSticks'] = None
                p['guess'] = None

            # Timeout für die Pick-Phase setzen
            set_pick_timeout(game_id, context.function_arn)

    games_table.put_item(Item=game)
    send_to_all(game_id, {'type': 'game_update', 'game': game})

    return {'statusCode': 200, 'body': json.dumps({'message': 'Guess submitted'})}

# --- Timer-Handler für EventBridge ---

def timer_handler(event, context):
    """Wird von EventBridge getriggert, um Spielphasen zu steuern."""
    action = event.get('action')
    game_id = event.get('gameId')

    if action == 'startGame':
        return start_game(game_id, context.function_arn)
    elif action == 'timeoutPick':
        return timeout_pick(game_id)

    return {'statusCode': 200}

def start_game(game_id, function_arn):
    """Startet das Spiel nach dem Countdown."""
    response = games_table.update_item(
        Key={'gameId': game_id},
        UpdateExpression="SET #s = :running, currentPhase = :pick",
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={':running': 'running', ':pick': 'pick'},
        ConditionExpression="#s = :waiting",
        ReturnValues="ALL_NEW"
    )
    updated_game = response['Attributes']

    # Timeout für die Pick-Phase setzen
    set_pick_timeout(game_id, function_arn)

    send_to_all(game_id, {'type': 'game_started', 'game': updated_game})
    # Regel löschen
    eventbridge.delete_rule(Name=f"{PROJECT_NAME}-start-game-{game_id}")
    return {'statusCode': 200}

def timeout_pick(game_id):
    """Setzt Hölzer für Spieler, die nicht gewählt haben, auf 3."""
    game = _get_game(game_id)
    if not game or game['currentPhase'] != 'pick':
        return {'statusCode': 200} # Nichts zu tun

    changed = False
    for p in game['players']:
        if not p['isEliminated'] and p['pickedSticks'] is None:
            p['pickedSticks'] = 3
            changed = True

    if changed:
        game['currentPhase'] = 'guess'
        games_table.put_item(Item=game)
        send_to_all(game_id, {'type': 'game_update', 'game': game})

    return {'statusCode': 200}

def set_pick_timeout(game_id, function_arn):
    """Erstellt eine EventBridge-Regel für das Pick-Timeout."""
    timeout = int(time.time()) + 30
    rule_name = f"{PROJECT_NAME}-pick-timeout-{game_id}"
    eventbridge.put_rule(
        Name=rule_name,
        ScheduleExpression=f"at({time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(timeout))})",
        State='ENABLED'
    )
    eventbridge.put_targets(
        Rule=rule_name,
        Targets=[{
            'Id': f"target-{game_id}",
            'Arn': function_arn,
            'Input': json.dumps({'action': 'timeoutPick', 'gameId': game_id})
        }]
    )

# lambda/ws_handler/main.py
# Dieser Code behandelt die WebSocket-Verbindungen

import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ.get('CONNECTIONS_TABLE_NAME'))

def connect_handler(event, context):
    """Wird aufgerufen, wenn ein Client eine WebSocket-Verbindung herstellt."""
    connection_id = event['requestContext']['connectionId']
    game_id = event.get('queryStringParameters', {}).get('gameId')

    if not game_id:
        return {'statusCode': 400, 'body': 'gameId query parameter is required.'}

    connections_table.put_item(
        Item={
            'connectionId': connection_id,
            'gameId': game_id
        }
    )
    return {'statusCode': 200, 'body': 'Connected.'}

def disconnect_handler(event, context):
    """Wird aufgerufen, wenn ein Client die Verbindung trennt."""
    connection_id = event['requestContext']['connectionId']
    connections_table.delete_item(Key={'connectionId': connection_id})
    return {'statusCode': 200, 'body': 'Disconnected.'}

def default_handler(event, context):
    """Standard-Handler für nicht erkannte WebSocket-Aktionen."""
    return {'statusCode': 400, 'body': 'Unrecognized action.'}
