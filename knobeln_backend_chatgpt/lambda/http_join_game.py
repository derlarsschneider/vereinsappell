import json, os
from common.util import resp, get_game_meta, now
import boto3

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event['pathParameters']['id']
    body = json.loads(event.get('body') or '{}')
    pid  = body.get('playerId')
    name = body.get('name','Player')
    game = get_game_meta(gid)
    if not game:
        return resp(404,{"error":"game not found"})
    if game.get('status') != 'waiting':
        return resp(403,{"error":"game already started"})

    # create player item if not exists
    try:
        table.put_item(Item={
            'PK': f'GAME#{gid}','SK': f'PLAYER#{pid}',
            'entity':'Player','playerId':pid,'name':name,
            'joinedAt': now(),'isEliminated': False,
            'GSI1PK': f'GAME#{gid}#PLAYERS','GSI1SK': f"{now()}#{pid}"
        }, ConditionExpression='attribute_not_exists(PK)')
    except Exception:
        pass

    table.update_item(
        Key={'PK': f'GAME#{gid}','SK': 'META'},
        UpdateExpression="SET #po = list_append(if_not_exists(#po, :empty), :pid), #c = if_not_exists(#c, :zero)+:one",
        ExpressionAttributeNames={'#po':'playerOrder','#c':'activePlayerCount'},
        ExpressionAttributeValues={':pid':[pid], ':empty':[], ':zero':0, ':one':1}
    )

    return resp(204)
