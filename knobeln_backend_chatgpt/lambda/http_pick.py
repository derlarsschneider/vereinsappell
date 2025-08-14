import json, os
from common.util import resp, now
import boto3

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event['pathParameters']['id']
    body = json.loads(event.get('body') or '{}')
    pid  = body.get('playerId')
    sticks = int(body.get('sticks',3))
    if sticks < 0 or sticks > 3:
        return resp(400,{"error":"sticks must be 0..3"})

    # find current round
    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    if not meta or meta.get('status') != 'running' or meta.get('phase') != 'pick':
        return resp(400,{"error":"not in pick phase"})
    rnd = int(meta.get('roundNumber',1))

    # write pick if not exists
    try:
        table.put_item(Item={
            'PK': f'GAME#{gid}','SK': f'ROUND#{rnd}#PICK#{pid}',
            'entity':'Pick','sticks': sticks,'pickedAt': now(),
            'GSI1PK': f'GAME#{gid}#PICKS#{rnd}','GSI1SK': f"{now()}#{pid}"
        }, ConditionExpression='attribute_not_exists(PK)')
    except Exception:
        return resp(409,{"error":"already picked"})

    return resp(204)
