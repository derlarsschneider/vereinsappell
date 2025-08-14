import os, json
from common.util import resp
import boto3

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    # resolve current game via lock
    lock = table.get_item(Key={'PK':'LOCK','SK':'GLOBAL#CURRENT_GAME'}).get('Item')
    if not lock:
        return resp(200,{"active": False})
    gid = lock['gameId']
    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    # load players
    players = table.query(
        IndexName='GSI1',
        KeyConditionExpression=boto3.dynamodb.conditions.Key('GSI1PK').eq(f'GAME#{gid}#PLAYERS')
    ).get('Items',[])
    return resp(200, {"active": True, "game": meta, "players": players})
