"""
Lambda function for handling player stick picking in the Knobeln game.
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
    Handle a player picking sticks in the Knobeln game.
    
    Expected event format:
    {
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": "player123"
                }
            },
            "connectionId": "abc123"
        },
        "pathParameters": {
            "gameId": "game123"
        },
        "body": "{\"count\": 2}"  # Number of sticks picked (0-3)
    }
    """
    try:
        # Parse the request
        try:
            game_id = event['pathParameters']['gameId']
            request_body = json.loads(event.get('body', '{}'))
            count = int(request_body.get('count', -1))
            
            if not 0 <= count <= 3:
                raise ValueError("Count must be between 0 and 3")
                
        except (KeyError, json.JSONDecodeError, ValueError) as e:
            logger.error(f"Invalid request: {e}")
            return utils.create_error_response(400, "Invalid request. Please provide a valid stick count (0-3).")
        
        # Get player info from the authorizer
        try:
            player_id = event['requestContext']['authorizer']['claims']['sub']
            connection_id = event['requestContext'].get('connectionId')
        except KeyError as e:
            logger.error(f"Missing required field in request: {e}")
            return utils.create_error_response(400, f"Missing required field: {e}")
        
        # Get the game from DynamoDB
        game_data = utils.get_game(game_id)
        if not game_data:
            return utils.create_error_response(404, "Game not found")
        
        # Check if the game is in the picking phase
        if game_data.get('phase') != GamePhase.PICKING:
            return utils.create_error_response(400, "It's not the picking phase")
        
        # Check if the player is in the game and not eliminated
        player = game_data['players'].get(player_id, {})
        if not player or player.get('is_eliminated', True):
            return utils.create_error_response(403, "You are not part of this game or have been eliminated")
        
        # Update the player's pick
        game_data['players'][player_id]['picked_sticks'] = count
        game_data['players'][player_id]['last_activity'] = utils.datetime.utcnow().isoformat()
        
        # Check if all players have picked
        active_players = [p for p in game_data['players'].values() 
                         if not p.get('is_eliminated', False)]
        all_picked = all('picked_sticks' in p for p in active_players)
        
        if all_picked:
            # Move to guessing phase
            game_data['phase'] = GamePhase.GUESSING
            
            # Set up the guessing order
            current_round = game_data['current_round']
            if not current_round:
                current_round = {
                    'round_number': len(game_data.get('rounds', [])) + 1,
                    'start_time': utils.datetime.utcnow().isoformat(),
                    'player_turn_order': [p['player_id'] for p in active_players],
                    'current_turn_index': 0,
                    'sticks_picked': {p['player_id']: p['picked_sticks'] for p in active_players},
                    'guesses': {}
                }
                game_data['current_round'] = current_round
            
            # Notify all players about the phase change and whose turn it is
            current_player_id = current_round['player_turn_order'][current_round['current_turn_index']]
            current_player_name = game_data['players'][current_player_id]['player_name']
            
            # Broadcast the phase change and turn information
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
            # Just acknowledge the pick
            broadcast_message = {
                'action': 'player_picked',
                'game_id': game_id,
                'player_id': player_id,
                'player_name': player['player_name'],
                'message': f"{player['player_name']} has picked their sticks"
            }
        
        # Save the updated game state
        utils.save_game(game_data)
        
        # Broadcast the update to all players
        utils.broadcast_message(game_id, broadcast_message)
        
        # Return success to the player who picked
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'game_id': game_id,
                'player_id': player_id,
                'count': count,
                'all_picked': all_picked
            })
        }
        
        logger.info(f"Player {player_id} picked {count} sticks in game {game_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error in pick_sticks: {e}", exc_info=True)
        return utils.create_error_response(500, "Internal server error")
