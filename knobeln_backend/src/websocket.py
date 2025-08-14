"""
Lambda function to handle WebSocket connections for the Knobeln game.
"""
import os
import json
import logging
import boto3
from botocore.exceptions import ClientError
import utils

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
api_gateway = boto3.client('apigatewaymanagementapi', 
                          endpoint_url=os.environ.get('WEBSOCKET_API'))

def lambda_handler(event, context):
    """
    Handle WebSocket events (connect, disconnect, message).
    
    Expected event formats:
    
    1. Connect:
    {
        "requestContext": {
            "routeKey": "$connect",
            "connectionId": "abc123",
            "domainName": "example.com",
            "stage": "prod"
        },
        "queryStringParameters": {
            "game_id": "game123"
        }
    }
    
    2. Disconnect:
    {
        "requestContext": {
            "routeKey": "$disconnect",
            "connectionId": "abc123"
        }
    }
    
    3. Message:
    {
        "requestContext": {
            "routeKey": "$default",
            "connectionId": "abc123"
        },
        "body": "{\"action\": \"ping\"}"
    }
    """
    route_key = event.get('requestContext', {}).get('routeKey')
    connection_id = event.get('requestContext', {}).get('connectionId')
    
    try:
        if route_key == '$connect':
            return handle_connect(event, connection_id)
        elif route_key == '$disconnect':
            return handle_disconnect(connection_id)
        elif route_key == '$default':
            return handle_message(event, connection_id)
        else:
            logger.warning(f"Unknown route key: {route_key}")
            return {'statusCode': 400, 'body': 'Unknown route key'}
    except Exception as e:
        logger.error(f"Error handling WebSocket {route_key}: {e}", exc_info=True)
        return {'statusCode': 500, 'body': 'Internal server error'}

def handle_connect(event, connection_id):
    """Handle a new WebSocket connection."""
    try:
        # Get the game ID from the query parameters
        game_id = event.get('queryStringParameters', {}).get('game_id')
        if not game_id:
            logger.error("No game_id provided in query parameters")
            return {'statusCode': 400, 'body': 'Missing game_id'}
        
        # Get the player's authentication token from the headers
        auth_header = event.get('headers', {}).get('Authorization')
        if not auth_header:
            logger.error("No Authorization header provided")
            return {'statusCode': 401, 'body': 'Unauthorized'}
        
        # For now, we'll just store the connection ID with the game ID
        # In a real implementation, you would validate the JWT token here
        # and associate the connection with the correct player
        
        # Store the connection in DynamoDB
        table = utils.get_table()
        
        # Get the current timestamp
        timestamp = utils.datetime.utcnow().isoformat()
        
        # Create or update the connection record
        table.put_item(
            Item={
                'game_id': game_id,
                'sk': f'CONNECTION#{connection_id}',
                'connection_id': connection_id,
                'connected_at': timestamp,
                'last_active': timestamp,
                'ttl': int(utils.datetime.utcnow().timestamp()) + 24 * 60 * 60  # 24 hours TTL
            }
        )
        
        logger.info(f"New WebSocket connection: {connection_id} for game {game_id}")
        return {'statusCode': 200, 'body': 'Connected'}
        
    except Exception as e:
        logger.error(f"Error in handle_connect: {e}", exc_info=True)
        return {'statusCode': 500, 'body': 'Internal server error'}

def handle_disconnect(connection_id):
    """Handle a WebSocket disconnection."""
    try:
        table = utils.get_table()
        
        # Find the connection record
        response = table.query(
            IndexName='ConnectionIndex',
            KeyConditionExpression='connection_id = :conn_id',
            ExpressionAttributeValues={
                ':conn_id': connection_id
            }
        )
        
        if not response.get('Items'):
            logger.warning(f"No connection record found for {connection_id}")
            return {'statusCode': 200, 'body': 'Disconnected'}
        
        # Get the game ID from the connection record
        connection_record = response['Items'][0]
        game_id = connection_record.get('game_id')
        
        # Delete the connection record
        table.delete_item(
            Key={
                'game_id': game_id,
                'sk': f'CONNECTION#{connection_id}'
            }
        )
        
        logger.info(f"WebSocket disconnected: {connection_id} from game {game_id}")
        return {'statusCode': 200, 'body': 'Disconnected'}
        
    except Exception as e:
        logger.error(f"Error in handle_disconnect: {e}", exc_info=True)
        return {'statusCode': 500, 'body': 'Internal server error'}

def handle_message(event, connection_id):
    """Handle an incoming WebSocket message."""
    try:
        # Parse the message body
        try:
            body = json.loads(event.get('body', '{}'))
            action = body.get('action')
            
            if not action:
                raise ValueError("Missing 'action' in message body")
                
        except (json.JSONDecodeError, ValueError) as e:
            logger.error(f"Invalid message format: {e}")
            return send_error(connection_id, "Invalid message format")
        
        # Get the connection record to find the game ID
        table = utils.get_table()
        
        response = table.query(
            IndexName='ConnectionIndex',
            KeyConditionExpression='connection_id = :conn_id',
            ExpressionAttributeValues={
                ':conn_id': connection_id
            }
        )
        
        if not response.get('Items'):
            logger.error(f"No connection record found for {connection_id}")
            return send_error(connection_id, "Connection not found")
        
        connection_record = response['Items'][0]
        game_id = connection_record.get('game_id')
        
        # Update the last active timestamp
        table.update_item(
            Key={
                'game_id': game_id,
                'sk': f'CONNECTION#{connection_id}'
            },
            UpdateExpression='SET last_active = :now',
            ExpressionAttributeValues={
                ':now': utils.datetime.utcnow().isoformat()
            }
        )
        
        # Route the message based on the action
        if action == 'ping':
            return send_message(connection_id, {'action': 'pong'})
        else:
            logger.warning(f"Unknown action: {action}")
            return send_error(connection_id, f"Unknown action: {action}")
        
    except Exception as e:
        logger.error(f"Error in handle_message: {e}", exc_info=True)
        return send_error(connection_id, "Internal server error")

def send_message(connection_id, message):
    """Send a message to a WebSocket connection."""
    try:
        if not isinstance(message, str):
            message = json.dumps(message)
            
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=message.encode('utf-8')
        )
        return {'statusCode': 200, 'body': 'Message sent'}
    except api_gateway.exceptions.GoneException:
        logger.warning(f"Connection {connection_id} is gone")
        return {'statusCode': 410, 'body': 'Connection gone'}
    except Exception as e:
        logger.error(f"Error sending message to {connection_id}: {e}")
        return {'statusCode': 500, 'body': 'Error sending message'}

def send_error(connection_id, error_message, status_code=400):
    """Send an error message to a WebSocket connection."""
    return send_message(connection_id, {
        'action': 'error',
        'error': error_message,
        'status_code': status_code
    })

def broadcast_to_game(game_id, message, exclude_connection_id=None):
    """Broadcast a message to all connections for a game."""
    try:
        table = utils.get_table()
        
        # Query for all connections for this game
        response = table.query(
            KeyConditionExpression='game_id = :game_id AND begins_with(sk, :prefix)',
            ExpressionAttributeValues={
                ':game_id': game_id,
                ':prefix': 'CONNECTION#'
            }
        )
        
        # Send the message to each connection
        for item in response.get('Items', []):
            conn_id = item.get('connection_id')
            
            # Skip the excluded connection (if any)
            if conn_id == exclude_connection_id:
                continue
                
            try:
                send_message(conn_id, message)
            except Exception as e:
                logger.error(f"Error broadcasting to {conn_id}: {e}")
                
        return True
    except Exception as e:
        logger.error(f"Error in broadcast_to_game: {e}", exc_info=True)
        return False
