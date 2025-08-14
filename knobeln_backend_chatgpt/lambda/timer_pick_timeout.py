import os, boto3
from common.util import now

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event.get('gameId'); rnd = int(event.get('round',1))
    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    if not meta or meta.get('phase') != 'pick' or meta.get('roundNumber') != rnd:
        return {"ok": True}
    # TODO: auto-assign missing picks=3, compute total, phase->guess, schedule guess-timeout
    table.update_item(Key={'PK': f'GAME#{gid}','SK':'META'},
                      UpdateExpression='SET #p=:guess',
                      ExpressionAttributeNames={'#p':'phase'},
                      ExpressionAttributeValues={':guess':'guess'})
    table.update_item(Key={'PK': f'GAME#{gid}','SK': f'ROUND#{rnd}'},
                      UpdateExpression='SET phase=:guess, guessDeadline=:dl',
                      ExpressionAttributeValues={':guess':'guess',':dl': now()+30})
    return {"ok": True}
