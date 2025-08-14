import json, os, uuid
from common.util import resp, put_lock_new_game, now, schedule_at
import boto3

table_name = os.environ['TABLE']
http_api_id = os.environ['HTTP_API_ID']
ddb = boto3.resource('dynamodb')
table = ddb.Table(table_name)
lam = boto3.client('lambda')

def handler(event, context):
    body = json.loads(event.get('body') or '{}')
    initiator_id = body.get('initiatorId') or str(uuid.uuid4())
    initiator_name = body.get('initiatorName','Player')

    game_id = str(uuid.uuid4())
    if not put_lock_new_game(game_id):
        return resp(409, {"error":"another game is active"})

    # add initiator as first player
    table.put_item(Item={
        'PK': f'GAME#{game_id}', 'SK': f'PLAYER#{initiator_id}',
        'entity':'Player','playerId':initiator_id,'name':initiator_name,
        'joinedAt': now(),'isEliminated': False,
        'GSI1PK': f'GAME#{game_id}#PLAYERS','GSI1SK': f"{now()}#{initiator_id}"
    })

    table.update_item(
        Key={'PK': f'GAME#{game_id}','SK':'META'},
        UpdateExpression="SET #startAt=:s, #playerOrder = list_append(if_not_exists(#playerOrder, :empty), :p), #active=:a",
        ExpressionAttributeNames={'#startAt':'startAt','#playerOrder':'playerOrder','#active':'activePlayerCount'},
        ExpressionAttributeValues={':s': now()+60, ':p':[initiator_id], ':empty':[], ':a':1}
    )

    # schedule start in 60s
    schedule_at("start-game", now()+60, os.environ['AWS_LAMBDA_FUNCTION_ARN'].replace('http-create-game','timer-start-game'),
                {"gameId":game_id})

    return resp(201, {"gameId":game_id})
