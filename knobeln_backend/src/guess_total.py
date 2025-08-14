"""
Lambda function for handling player guesses in the Knobeln game.
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
    Handle a player's guess of the total number of sticks.
    
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
        "body": "{\"guess\": 5}"  # Player's guess of total sticks
    }
    """
    try:
        # Parse the request
        try:
            game_id = event['pathParameters']['gameId']
            request_body = json.loads(event.get('body', '{}'))
            guess = int(request_body.get('guess', -1))
            
            if guess < 0:
                raise ValueError("Guess must be a non-negative number")
                
        except (KeyError, json.JSONDecodeError, ValueError) as e:
            logger.error(f"Invalid request: {e}")
            return utils.create_error_response(400, "Invalid request. Please provide a valid guess.")
        
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
        
        # Check if the game is in the guessing phase
        if game_data.get('phase') != GamePhase.GUESSING:
            return utils.create_error_response(400, "It's not the guessing phase")
        
        # Check if it's the player's turn
        current_round = game_data.get('current_round', {})
        if not current_round:
            return utils.create_error_response(400, "No active round")
            
        current_player_id = current_round.get('player_turn_order', [])[current_round.get('current_turn_index', 0)]
        if player_id != current_player_id:
            return utils.create_error_response(403, "It's not your turn to guess")
        
        # Check if the player is in the game and not eliminated
        player = game_data['players'].get(player_id, {})
        if not player or player.get('is_eliminated', True):
            return utils.create_error_response(403, "You are not part of this game or have been eliminated")
        
        # Check if the guess is valid
        active_players = [p for p in game_data['players'].values() 
                         if not p.get('is_eliminated', False)]
        min_possible = 0
        max_possible = 3 * len(active_players)
        
        if not min_possible <= guess <= max_possible:
            return utils.create_error_response(
                400, 
                f"Guess must be between {min_possible} and {max_possible}"
            )
        
        # Check if the guess is already taken (except for the last player)
        existing_guesses = list(current_round.get('guesses', {}).values())
        if guess in existing_guesses and len(existing_guesses) < len(active_players) - 1:
            return utils.create_error_response(400, "This guess is already taken")
        
        # Record the guess
        if 'guesses' not in current_round:
            current_round['guesses'] = {}
        current_round['guesses'][player_id] = guess
        
        # Update the player's last activity
        game_data['players'][player_id]['last_activity'] = utils.datetime.utcnow().isoformat()
        
        # Check if all players have guessed
        all_guessed = len(current_round.get('guesses', {})) == len(active_players)
        
        if all_guessed:
            # Calculate the total number of sticks
            total_sticks = sum(p.get('picked_sticks', 0) 
                             for p in game_data['players'].values() 
                             if not p.get('is_eliminated', False))
            
            # Find the winner(s) - players who guessed the correct total
            winners = [
                (pid, g) for pid, g in current_round['guesses'].items() 
                if g == total_sticks
            ]
            
            # Determine the round winner (first to guess correctly, if any)
            round_winner_id = None
            if winners:
                # If multiple winners, the one who guessed first wins
                winner_id, winner_guess = min(
                    winners,
                    key=lambda x: list(current_round['guesses'].keys()).index(x[0])
                )
                round_winner_id = winner_id
                
                # Eliminate the winner
                game_data['players'][winner_id]['is_eliminated'] = True
                
                # Check if the game is over (only one player left)
                active_players = [p for p in game_data['players'].values() 
                                if not p.get('is_eliminated', False)]
                
                if len(active_players) <= 1:
                    # Game over - last remaining player is the loser
                    game_data['phase'] = GamePhase.FINISHED
                    game_data['ended_at'] = utils.datetime.utcnow().isoformat()
                    
                    if len(active_players) == 1:
                        loser_id = active_players[0]['player_id']
                        game_data['loser_id'] = loser_id
                        
                        # Broadcast game over
                        broadcast_message = {
                            'action': 'game_over',
                            'game_id': game_id,
                            'winner_id': winner_id,
                            'winner_name': game_data['players'][winner_id]['player_name'],
                            'loser_id': loser_id,
                            'loser_name': active_players[0]['player_name'],
                            'total_sticks': total_sticks,
                            'message': f"Game over! {game_data['players'][winner_id]['player_name']} wins!"
                        }
                    else:
                        # Shouldn't happen, but handle just in case
                        broadcast_message = {
                            'action': 'game_over',
                            'game_id': game_id,
                            'winner_id': winner_id,
                            'winner_name': game_data['players'][winner_id]['player_name'],
                            'total_sticks': total_sticks,
                            'message': f"Game over! {game_data['players'][winner_id]['player_name']} wins!"
                        }
                else:
                    # Start a new round
                    game_data['phase'] = GamePhase.PICKING
                    
                    # Reset player picks for the new round
                    for p in game_data['players'].values():
                        if 'picked_sticks' in p:
                            del p['picked_sticks']
                    
                    # Broadcast the winner and new round
                    broadcast_message = {
                        'action': 'round_complete',
                        'game_id': game_id,
                        'winner_id': winner_id,
                        'winner_name': game_data['players'][winner_id]['player_name'],
                        'total_sticks': total_sticks,
                        'phase': 'PICKING',
                        'message': f"{game_data['players'][winner_id]['player_name']} guessed correctly and is eliminated! New round starting..."
                    }
            else:
                # No correct guesses, start a new round
                game_data['phase'] = GamePhase.PICKING
                
                # Reset player picks for the new round
                for p in game_data['players'].values():
                    if 'picked_sticks' in p:
                        del p['picked_sticks']
                
                # Broadcast the result and new round
                broadcast_message = {
                    'action': 'round_complete',
                    'game_id': game_id,
                    'total_sticks': total_sticks,
                    'phase': 'PICKING',
                    'message': f"No one guessed correctly! The total was {total_sticks}. New round starting..."
                }
            
            # Save the current round to history
            current_round['end_time'] = utils.datetime.utcnow().isoformat()
            if 'rounds' not in game_data:
                game_data['rounds'] = []
            game_data['rounds'].append(current_round)
            
            # If the game isn't over, start a new round
            if game_data['phase'] == GamePhase.PICKING:
                # Create a new round
                new_round_number = len(game_data['rounds']) + 1
                
                # Rotate the player order for the new round
                player_order = [p['player_id'] for p in active_players]
                if new_round_number > 1:
                    next_player_index = (new_round_number - 1) % len(player_order)
                    player_order = player_order[next_player_index:] + player_order[:next_player_index]
                
                game_data['current_round'] = {
                    'round_number': new_round_number,
                    'start_time': utils.datetime.utcnow().isoformat(),
                    'player_turn_order': player_order,
                    'current_turn_index': 0,
                    'sticks_picked': {},
                    'guesses': {}
                }
        else:
            # Move to the next player's turn
            current_round['current_turn_index'] = (current_round['current_turn_index'] + 1) % len(active_players)
            next_player_id = current_round['player_turn_order'][current_round['current_turn_index']]
            next_player_name = game_data['players'][next_player_id]['player_name']
            
            # Acknowledge the guess and inform about the next player
            broadcast_message = {
                'action': 'guess_received',
                'game_id': game_id,
                'player_id': player_id,
                'player_name': player['player_name'],
                'guess': guess,
                'next_player': {
                    'player_id': next_player_id,
                    'player_name': next_player_name
                },
                'message': f"{player['player_name']} guessed {guess}. It's now {next_player_name}'s turn."
            }
        
        # Save the updated game state
        utils.save_game(game_data)
        
        # Broadcast the update to all players
        utils.broadcast_message(game_id, broadcast_message)
        
        # Return success to the player who guessed
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'game_id': game_id,
                'player_id': player_id,
                'guess': guess,
                'all_guessed': all_guessed
            })
        }
        
        logger.info(f"Player {player_id} guessed {guess} in game {game_id}")
        return response
        
    except Exception as e:
        logger.error(f"Error in guess_total: {e}", exc_info=True)
        return utils.create_error_response(500, "Internal server error")
