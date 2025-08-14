"""
Lambda function to start a Knobeln game after the initial delay.
Triggered by EventBridge.
"""
import os
import json
import logging
from models import GamePhase
import utils

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle the start of a Knobeln game after the initial delay.
    
    Expected event format (from EventBridge):
    {
        "source": "knobeln.game",
        "detail-type": "GameStartScheduled",
        "detail": {
            "game_id": "game123",
            "scheduled_time": "2023-01-01T12:00:00Z"
        }
    }
    """
    try:
        # Parse the event
        try:
            detail = event.get('detail', {})
            game_id = detail.get('game_id')
            
            if not game_id:
                raise ValueError("Missing game_id in event detail")
                
        except (KeyError, ValueError) as e:
            logger.error(f"Invalid event: {e}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid event format',
                    'details': str(e)
                })
            }
        
        # Get the game from DynamoDB
        game_data = utils.get_game(game_id)
        if not game_data:
            logger.error(f"Game {game_id} not found")
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'Game not found',
                    'game_id': game_id
                })
            }
        
        # Check if the game has already started
        if game_data.get('phase') != GamePhase.WAITING:
            logger.info(f"Game {game_id} is already in phase {game_data.get('phase')}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Game already started',
                    'game_id': game_id,
                    'phase': game_data.get('phase')
                })
            }
        
        # Check if there are enough players (at least 2)
        active_players = [p for p in game_data.get('players', {}).values() 
                         if not p.get('is_eliminated', False)]
        
        if len(active_players) < 2:
            # Not enough players, cancel the game
            game_data['phase'] = GamePhase.FINISHED
            game_data['ended_at'] = utils.datetime.utcnow().isoformat()
            game_data['settings']['cancellation_reason'] = "Not enough players to start"
            
            utils.save_game(game_data)
            
            # Notify all players
            utils.broadcast_message(game_id, {
                'action': 'game_cancelled',
                'game_id': game_id,
                'reason': 'Not enough players to start the game',
                'message': 'Game cancelled: Not enough players to start'
            })
            
            logger.info(f"Game {game_id} cancelled: Not enough players")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Game cancelled: Not enough players',
                    'game_id': game_id
                })
            }
        
        # Start the game
        game_data['phase'] = GamePhase.PICKING
        game_data['started_at'] = utils.datetime.utcnow().isoformat()
        
        # Create the first round
        round_number = 1
        player_order = [p['player_id'] for p in active_players]
        
        game_data['current_round'] = {
            'round_number': round_number,
            'start_time': utils.datetime.utcnow().isoformat(),
            'player_turn_order': player_order,
            'current_turn_index': 0,
            'sticks_picked': {},
            'guesses': {}
        }
        
        # Save the updated game state
        utils.save_game(game_data)
        
        # Notify all players that the game has started
        utils.broadcast_message(game_id, {
            'action': 'game_started',
            'game_id': game_id,
            'round_number': round_number,
            'player_order': [
                {
                    'player_id': pid,
                    'player_name': game_data['players'][pid]['player_name']
                }
                for pid in player_order
            ],
            'message': 'The game has started! Pick your sticks (0-3).',
            'phase': 'PICKING'
        })
        
        logger.info(f"Game {game_id} started with {len(active_players)} players")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Game started successfully',
                'game_id': game_id,
                'player_count': len(active_players)
            })
        }
        
    except Exception as e:
        logger.error(f"Error starting game: {e}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
