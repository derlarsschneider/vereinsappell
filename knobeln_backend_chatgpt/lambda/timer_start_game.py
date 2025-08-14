import os
import boto3
from common.util import now

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event.get('gameId')
    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    if not meta or meta.get('status') != 'waiting':
        return {"ok": True}
    # switch to running/pick round 1 + set pick deadline
    table.update_item(
        Key={'PK': f'GAME#{gid}','SK':'META'},
        UpdateExpression='SET #s=:run, #p=:pick, #r=:r1',
        ExpressionAttributeNames={'#s':'status','#p':'phase','#r':'roundNumber'},
        ExpressionAttributeValues={':run':'running',':pick':'pick',':r1':1}
    )
    table.put_item(Item={'PK': f'GAME#{gid}','SK': 'ROUND#1','entity':'Round','phase':'pick','pickDeadline': now()+30})
    return {"ok": True}
