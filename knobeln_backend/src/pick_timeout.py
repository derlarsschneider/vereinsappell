"""
Lambda function to handle timeouts when players take too long to pick sticks.
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
    Handle a player timeout during the picking phase.
    
    Expected event format (from EventBridge):
    {
        "source": "knobeln.game",
        "detail-type": "PickTimeoutScheduled",
        "detail": {
            "game_id": "game123",
            "player_id": "player123",
            "round_number": 1,
            "scheduled_time": "2023-01-01T12:00:00Z"
        }
    }
    """
    try:
        # Parse the event
        try:
            detail = event.get('detail', {})
            game_id = detail.get('game_id')
            player_id = detail.get('player_id')
            round_number = detail.get('round_number')
            
            if not all([game_id, player_id, round_number]):
                raise ValueError("Missing required fields in event detail")
                
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
        
        # Check if the game is still in the picking phase
        if game_data.get('phase') != GamePhase.PICKING:
            logger.info(f"Game {game_id} is no longer in the picking phase")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Game is no longer in the picking phase',
                    'game_id': game_id,
                    'phase': game_data.get('phase')
                })
        }
        
        # Check if the round number matches
        current_round = game_data.get('current_round', {})
        if current_round.get('round_number') != round_number:
            logger.info(f"Round {round_number} is no longer the current round in game {game_id}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Round number does not match current round',
                    'game_id': game_id,
                    'expected_round': round_number,
                    'current_round': current_round.get('round_number')
                })
        }
        
        # Check if the player has already picked
        player = game_data['players'].get(player_id, {})
        if not player:
            logger.error(f"Player {player_id} not found in game {game_id}")
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'Player not found in game',
                    'game_id': game_id,
                    'player_id': player_id
                })
        }
        
        if 'picked_sticks' in player:
            logger.info(f"Player {player_id} has already picked in game {game_id}")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Player has already picked',
                    'game_id': game_id,
                    'player_id': player_id
                })
            }
        
        # The player has timed out - assign a random number of sticks (0-3)
        import random
        picked_sticks = random.randint(0, 3)
        player['picked_sticks'] = picked_sticks
        
        # Update the player's last activity
        player['last_activity'] = utils.datetime.utcnow().isoformat()
        
        # Check if all players have picked
        active_players = [p for p in game_data['players'].values() 
                         if not p.get('is_eliminated', False)]
        all_picked = all('picked_sticks' in p for p in active_players)
        
        if all_picked:
            # Move to guessing phase
            game_data['phase'] = GamePhase.GUESSING
            
            # Record the picks in the current round
            current_round['sticks_picked'] = {
                p['player_id']: p['picked_sticks'] 
                for p in active_players
            }
            
            # Set up the first guesser
            current_round['current_turn_index'] = 0
            current_player_id = current_round['player_turn_order'][0]
            current_player_name = game_data['players'][current_player_id]['player_name']
            
            # Notify all players about the phase change and first guesser
            broadcast_message = {
                'action': 'phase_changed',
                'game_id': game_id,
                'phase': 'GUESSING',
                'current_player': {
                    'player_id': current_player_id,
                    'player_name': current_player_name
                },
                'message': f"All players have picked. It's {current_player_name}'s turn to guess."
            }
        else:
            # Just notify about the auto-pick
            broadcast_message = {
                'action': 'player_picked',
                'game_id': game_id,
                'player_id': player_id,
                'player_name': player['player_name'],
                'auto_pick': True,
                'count': picked_sticks,
                'message': f"{player['player_name']} was assigned {picked_sticks} sticks (auto-pick)"
            }
        
        # Save the updated game state
        utils.save_game(game_data)
        
        # Broadcast the update to all players
        utils.broadcast_message(game_id, broadcast_message)
        
        logger.info(f"Auto-picked {picked_sticks} sticks for player {player_id} in game {game_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Auto-pick completed',
                'game_id': game_id,
                'player_id': player_id,
                'picked_sticks': picked_sticks,
                'all_picked': all_picked
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling pick timeout: {e}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
