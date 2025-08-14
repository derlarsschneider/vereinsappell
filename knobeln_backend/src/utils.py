"""
Utility functions for the Knobeln game backend.
"""
import os
import json
import boto3
import logging
from typing import Dict, Any, Optional, List
from botocore.exceptions import ClientError
from datetime import datetime

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
apigw_management = boto3.client('apigatewaymanagementapi', endpoint_url=os.environ.get('WEBSOCKET_API'))
events = boto3.client('events')


def get_table():
    """Get the DynamoDB table."""
    table_name = os.environ['DYNAMODB_TABLE']
    return dynamodb.Table(table_name)


def get_game(game_id: str) -> Dict[str, Any]:
    """
    Retrieve a game from DynamoDB.
    
    Args:
        game_id: The ID of the game to retrieve
        
    Returns:
        Dict containing the game data or None if not found
    """
    try:
        table = get_table()
        response = table.get_item(
            Key={
                'game_id': game_id,
                'sk': 'GAME'
            }
        )
        return response.get('Item')
    except ClientError as e:
        logger.error(f"Error getting game {game_id}: {e}")
        raise


def save_game(game_data: Dict[str, Any]) -> None:
    """
    Save a game to DynamoDB.
    
    Args:
        game_data: The game data to save
    """
    try:
        table = get_table()
        
        # Ensure the sort key is set
        if 'sk' not in game_data:
            game_data['sk'] = 'GAME'
        
        # Update the last updated timestamp
        game_data['updated_at'] = datetime.utcnow().isoformat()
        
        # Save the game
        table.put_item(Item=game_data)
    except ClientError as e:
        logger.error(f"Error saving game {game_data.get('game_id')}: {e}")
        raise


def send_ws_message(connection_id: str, message: Dict[str, Any]) -> bool:
    """
    Send a WebSocket message to a specific connection.
    
    Args:
        connection_id: The WebSocket connection ID
        message: The message to send (will be JSON-serialized)
        
    Returns:
        bool: True if the message was sent successfully, False otherwise
    """
    try:
        apigw_management.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message)
        )
        return True
    except Exception as e:
        logger.error(f"Error sending message to {connection_id}: {e}")
        return False


def broadcast_message(game_id: str, message: Dict[str, Any], exclude_connections: List[str] = None) -> None:
    """
    Broadcast a message to all connected players in a game.
    
    Args:
        game_id: The ID of the game
        message: The message to broadcast
        exclude_connections: List of connection IDs to exclude from the broadcast
    """
    if exclude_connections is None:
        exclude_connections = []
    
    try:
        # Get the game to find all players
        game = get_game(game_id)
        if not game:
            logger.error(f"Game {game_id} not found for broadcast")
            return
        
        # Send the message to all connected players
        for player in game.get('players', {}).values():
            connection_id = player.get('connection_id')
            if connection_id and connection_id not in exclude_connections:
                send_ws_message(connection_id, message)
    except Exception as e:
        logger.error(f"Error broadcasting message to game {game_id}: {e}")


def schedule_event(rule_name: str, delay_seconds: int, detail: Dict[str, Any]) -> str:
    """
    Schedule an EventBridge event with a delay.
    
    Args:
        rule_name: The name of the EventBridge rule
        delay_seconds: The delay in seconds before the event is triggered
        detail: The event detail to include
        
    Returns:
        str: The ID of the scheduled event
    """
    try:
        # Create a scheduled rule
        response = events.put_rule(
            Name=rule_name,
            ScheduleExpression=f"rate({delay_seconds} seconds)",
            State='ENABLED',
            Description=f"Scheduled event for {rule_name}"
        )
        
        # Add a target to the rule
        event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        
        events.put_targets(
            Rule=rule_name,
            Targets=[
                {
                    'Id': '1',
                    'Arn': os.environ['EVENT_TARGET_ARN'],
                    'Input': json.dumps({
                        'source': 'knobeln.game',
                        'detail-type': rule_name,
                        'detail': detail
                    })
                }
            ]
        )
        
        return response['RuleArn']
    except Exception as e:
        logger.error(f"Error scheduling event {rule_name}: {e}")
        raise


def cancel_scheduled_event(rule_name: str) -> None:
    """
    Cancel a scheduled EventBridge event.
    
    Args:
        rule_name: The name of the EventBridge rule to cancel
    """
    try:
        # Remove all targets from the rule
        targets = events.list_targets_by_rule(Rule=rule_name)
        if targets.get('Targets'):
            events.remove_targets(
                Rule=rule_name,
                Ids=[t['Id'] for t in targets['Targets']]
            )
        
        # Delete the rule
        events.delete_rule(Name=rule_name)
    except Exception as e:
        logger.error(f"Error canceling scheduled event {rule_name}: {e}")


def get_connection_game_id(connection_id: str) -> Optional[str]:
    """
    Find the game ID associated with a WebSocket connection.
    
    Args:
        connection_id: The WebSocket connection ID
        
    Returns:
        str: The game ID if found, None otherwise
    """
    try:
        table = get_table()
        
        # Query the GSI to find the game for this connection
        response = table.query(
            IndexName='ConnectionIndex',
            KeyConditionExpression='connection_id = :conn_id',
            ExpressionAttributeValues={
                ':conn_id': connection_id
            },
            Limit=1
        )
        
        if response.get('Items'):
            return response['Items'][0].get('game_id')
        return None
    except Exception as e:
        logger.error(f"Error finding game for connection {connection_id}: {e}")
        return None


def validate_player_in_game(game_data: Dict[str, Any], player_id: str) -> Dict[str, Any]:
    """
    Validate that a player is in the game and return their data.
    
    Args:
        game_data: The game data
        player_id: The player ID to validate
        
    Returns:
        Dict: The player data if found
        
    Raises:
        ValueError: If the player is not in the game
    """
    player = game_data.get('players', {}).get(player_id)
    if not player:
        raise ValueError("Player not found in this game")
    return player


def get_connected_players(game_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Get a list of players with active WebSocket connections.
    
    Args:
        game_data: The game data
        
    Returns:
        List of player data for connected players
    """
    return [
        player for player in game_data.get('players', {}).values()
        if player.get('connection_id')
    ]


def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """
    Create a standardized error response.
    
    Args:
        status_code: HTTP status code
        message: Error message
        
    Returns:
        Dict containing the error response
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message
        })
    }
