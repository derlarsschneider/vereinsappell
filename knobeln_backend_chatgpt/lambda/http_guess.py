import json, os
from common.util import resp, now
import boto3

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event['pathParameters']['id']
    body = json.loads(event.get('body') or '{}')
    pid  = body.get('playerId')
    guess = int(body.get('guess'))

    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    if not meta or meta.get('status') != 'running' or meta.get('phase') != 'guess':
        return resp(400,{"error":"not in guess phase"})
    rnd = int(meta.get('roundNumber',1))

    # lock via map key not exists
    try:
        table.update_item(
            Key={'PK': f'GAME#{gid}','SK': f'ROUND#{rnd}'},
            UpdateExpression='SET guessedNumbers.#g = :pid',
            ExpressionAttributeNames={'#g': str(guess)},
            ExpressionAttributeValues={':pid': pid},
            ConditionExpression='attribute_not_exists(guessedNumbers.#g)'
        )
    except Exception:
        return resp(409,{"error":"guess already taken"})

    # store individual guess (optional)
    table.put_item(Item={
        'PK': f'GAME#{gid}','SK': f'ROUND#{rnd}#GUESS#{pid}',
        'entity':'Guess','guess': guess,'guessedAt': now(),
        'GSI1PK': f'GAME#{gid}#GUESSES#{rnd}','GSI1SK': f"{now()}#{pid}"
    })

    return resp(204)
