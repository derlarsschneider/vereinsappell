"""
Lambda function for retrieving the current state of a Knobeln game.
"""
import os
import json
import logging
import utils

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle a request to get the current state of a Knobeln game.
    
    Expected event format:
    {
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": "player123"
                }
            },
            "connectionId": "abc123"  # Optional for WebSocket connections
        },
        "pathParameters": {
            "gameId": "game123"
        }
    }
    """
    try:
        # Parse the request
        try:
            game_id = event['pathParameters']['gameId']
        except KeyError as e:
            logger.error(f"Missing required field in request: {e}")
            return utils.create_error_response(400, f"Missing required field: {e}")
        
        # Get player info from the authorizer (if available)
        player_id = None
        try:
            player_id = event['requestContext']['authorizer']['claims']['sub']
        except (KeyError, TypeError):
            # Not all endpoints require authentication
            pass
        
        # Get the game from DynamoDB
        game_data = utils.get_game(game_id)
        if not game_data:
            return utils.create_error_response(404, "Game not found")
        
        # If a player ID was provided, verify the player is in the game
        if player_id and player_id not in game_data.get('players', {}):
            return utils.create_error_response(403, "You are not part of this game")
        
        # Prepare the response data
        response_data = {
            'game_id': game_data['game_id'],
            'phase': game_data.get('phase', 'WAITING'),
            'created_at': game_data.get('created_at'),
            'started_at': game_data.get('started_at'),
            'ended_at': game_data.get('ended_at'),
            'settings': game_data.get('settings', {}),
            'players': [],
            'current_round': None,
            'rounds': game_data.get('rounds', []),
            'winner_id': game_data.get('winner_id'),
            'loser_id': game_data.get('loser_id')
        }
        
        # Add player information (without sensitive data)
        for pid, player in game_data.get('players', {}).items():
            player_data = {
                'player_id': pid,
                'player_name': player.get('player_name', 'Player'),
                'is_creator': player.get('is_creator', False),
                'is_eliminated': player.get('is_eliminated', False),
                'score': player.get('score', 0)
            }
            
            # Only include the current player's pick (if any)
            if pid == player_id and 'picked_sticks' in player:
                player_data['picked_sticks'] = player['picked_sticks']
            
            response_data['players'].append(player_data)
        
        # Add current round information if available
        if 'current_round' in game_data and game_data['current_round']:
            round_data = game_data['current_round'].copy()
            
            # Only include picks if the round is complete
            if game_data.get('phase') != 'PICKING':
                if 'sticks_picked' in round_data:
                    round_data['sticks_picked'] = {
                        pid: count for pid, count in round_data['sticks_picked'].items()
                    }
            else:
                # In picking phase, only include the player's own pick
                if player_id and 'sticks_picked' in round_data:
                    if player_id in round_data['sticks_picked']:
                        round_data['sticks_picked'] = {
                            player_id: round_data['sticks_picked'][player_id]
                        }
                    else:
                        round_data['sticks_picked'] = {}
            
            # Only include guesses if it's the guessing phase and it's the player's turn
            if game_data.get('phase') == 'GUESSING' and 'guesses' in round_data:
                current_player_id = round_data['player_turn_order'][round_data['current_turn_index']]
                
                if player_id == current_player_id:
                    # Show all guesses to the current player
                    round_data['guesses'] = round_data['guesses']
                else:
                    # Only show the player's own guess
                    round_data['guesses'] = {
                        k: v for k, v in round_data['guesses'].items() 
                        if k == player_id
                    }
            
            response_data['current_round'] = round_data
        
        # Return the game state
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
        
        logger.info(f"Retrieved game state for game {game_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error getting game state: {e}", exc_info=True)
        return utils.create_error_response(500, "Internal server error")
