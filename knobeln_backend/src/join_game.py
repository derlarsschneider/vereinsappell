"""
Lambda function for joining an existing Knobeln game.
"""
import os
import json
import logging
from models import Player, GamePhase
import utils

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle a player joining an existing Knobeln game.
    
    Expected event format:
    {
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": "player123",
                    "cognito:username": "player2",
                    "email": "player2@example.com"
                }
            },
            "connectionId": "def456"
        },
        "pathParameters": {
            "gameId": "game123"
        },
        "body": "{}"  # Optional player preferences
    }
    """
    try:
        # Parse the request
        try:
            game_id = event['pathParameters']['gameId']
            request_body = json.loads(event.get('body', '{}'))
        except (KeyError, json.JSONDecodeError) as e:
            logger.error(f"Invalid request: {e}")
            return utils.create_error_response(400, "Invalid request")
        
        # Get player info from the authorizer
        try:
            claims = event['requestContext']['authorizer']['claims']
            player_id = claims['sub']
            player_name = claims.get('cognito:username', 'Player')
            connection_id = event['requestContext'].get('connectionId')
        except KeyError as e:
            logger.error(f"Missing required field in request: {e}")
            return utils.create_error_response(400, f"Missing required field: {e}")
        
        # Get the game from DynamoDB
        game_data = utils.get_game(game_id)
        if not game_data:
            return utils.create_error_response(404, "Game not found")
        
        # Check if the game has already started
        if game_data.get('phase') != GamePhase.WAITING:
            return utils.create_error_response(400, "Game has already started")
        
        # Check if the player is already in the game
        if player_id in game_data.get('players', {}):
            # Update the player's connection ID if they're reconnecting
            game_data['players'][player_id]['connection_id'] = connection_id
            player_name = game_data['players'][player_id]['player_name']
            action = "reconnected"
        else:
            # Check if the game is full
            max_players = game_data.get('settings', {}).get('max_players', 10)
            if len(game_data.get('players', {})) >= max_players:
                return utils.create_error_response(400, "Game is full")
            
            # Add the new player to the game
            game_data['players'][player_id] = {
                'player_id': player_id,
                'player_name': player_name,
                'connection_id': connection_id,
                'is_creator': False,
                'is_eliminated': False,
                'last_activity': utils.datetime.utcnow().isoformat()
            }
            action = "joined"
        
        # Save the updated game to DynamoDB
        utils.save_game(game_data)
        
        # Notify all players about the new player
        player_list = [
            {
                'player_id': pid,
                'player_name': p['player_name'],
                'is_creator': p.get('is_creator', False)
            }
            for pid, p in game_data.get('players', {}).items()
        ]
        
        # Broadcast the player list update to all connected players
        utils.broadcast_message(game_id, {
            'action': 'player_updated',
            'game_id': game_id,
            'players': player_list,
            'message': f"{player_name} has {action} the game"
        })
        
        # Return the game details to the joining player
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'game_id': game_id,
                'player_id': player_id,
                'player_name': player_name,
                'action': action,
                'players': player_list,
                'settings': game_data.get('settings', {})
            })
        }
        
        logger.info(f"Player {player_name} {action} game {game_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error joining game: {e}", exc_info=True)
        return utils.create_error_response(500, "Internal server error")
