import os, boto3

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def handler(event, context):
    gid = event.get('gameId'); rnd = int(event.get('round',1))
    meta = table.get_item(Key={'PK': f'GAME#{gid}','SK':'META'}).get('Item')
    if not meta or meta.get('phase') != 'guess' or meta.get('roundNumber') != rnd:
        return {"ok": True}
    # TODO: finalize round, eliminate correct guessers, start next round or finish
    return {"ok": True}
