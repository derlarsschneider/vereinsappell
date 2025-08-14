"""
Lambda function for creating a new Knobeln game.
"""
import os
import json
import uuid
import logging
from datetime import datetime, timedelta
from models import Game, Player, GamePhase
import utils

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle the creation of a new Knobeln game.
    
    Expected event format:
    {
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": "player123",
                    "cognito:username": "player1",
                    "email": "player1@example.com"
                }
            },
            "connectionId": "abc123"
        },
        "body": "{}"  # Optional settings
    }
    """
    try:
        # Parse the request
        try:
            request_body = json.loads(event.get('body', '{}'))
        except json.JSONDecodeError:
            return utils.create_error_response(400, "Invalid JSON in request body")
        
        # Get player info from the authorizer
        try:
            claims = event['requestContext']['authorizer']['claims']
            player_id = claims['sub']
            player_name = claims.get('cognito:username', 'Player')
            connection_id = event['requestContext'].get('connectionId')
        except KeyError as e:
            logger.error(f"Missing required field in request: {e}")
            return utils.create_error_response(400, f"Missing required field: {e}")
        
        # Create a new game ID
        game_id = str(uuid.uuid4())
        
        # Create the game object
        game = Game(
            game_id=game_id,
            phase=GamePhase.WAITING,
            settings={
                'game_start_delay': int(os.environ.get('GAME_START_DELAY', 60)),
                'pick_timeout': int(os.environ.get('PICK_TIMEOUT', 30)),
                'max_players': 10,  # Default max players
                **request_body.get('settings', {})  # Allow overriding settings
            }
        )
        
        # Add the creator as the first player
        game.players[player_id] = Player(
            player_id=player_id,
            player_name=player_name,
            connection_id=connection_id,
            is_creator=True
        )
        
        # Save the game to DynamoDB
        game_data = json.loads(game.json(by_alias=True))
        utils.save_game(game_data)
        
        # Schedule the game start
        start_time = datetime.utcnow() + timedelta(seconds=game.settings['game_start_delay'])
        schedule_rule_name = f"knobeln-start-game-{game_id}"
        
        utils.schedule_event(
            rule_name=schedule_rule_name,
            delay_seconds=game.settings['game_start_delay'],
            detail={
                'game_id': game_id,
                'scheduled_time': start_time.isoformat()
            }
        )
        
        # Return the game ID and start time to the creator
        response = {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'game_id': game_id,
                'start_time': start_time.isoformat(),
                'player_id': player_id,
                'player_name': player_name
            })
        }
        
        logger.info(f"Created new game {game_id} with creator {player_name}")
        return response
        
    except Exception as e:
        logger.error(f"Error creating game: {e}", exc_info=True)
        return utils.create_error_response(500, "Internal server error")

def schedule_rule_name(game_id: str) -> str:
    """Generate a unique rule name for the game start event."""
    return f"knobeln-start-game-{game_id}"
