import os, json, time, uuid, boto3, decimal
from boto3.dynamodb.conditions import Key

ddb = boto3.resource('dynamodb')
table = ddb.Table(os.environ['TABLE'])

def now():
    return int(time.time())

def resp(status, body=None):
    return {"statusCode": status, "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}, "body": json.dumps(body or {})}

def get_game_meta(game_id):
    r = table.get_item(Key={"PK": f"GAME#{game_id}", "SK": "META"})
    return r.get('Item')

def put_lock_new_game(game_id):
    client = boto3.client('dynamodb')
    try:
        client.transact_write_items(TransactItems=[
            {"Put": {
                "TableName": os.environ['TABLE'],
                "Item": {"PK": {"S": f"GAME#{game_id}"}, "SK": {"S": "META"},
                         "entity": {"S": "Game"}, "status": {"S": "waiting"},
                         "roundNumber": {"N": "0"}, "phase": {"S": ""},
                         "playerOrder": {"L": []}, "activePlayerCount": {"N": "0"},
                         "createdAt": {"N": str(now())}
                         }
            }},
            {"ConditionCheck": {
                "TableName": os.environ['TABLE'],
                "Key": {"PK": {"S": "LOCK"}, "SK": {"S": "GLOBAL#CURRENT_GAME"}},
                "ConditionExpression": "attribute_not_exists(PK) OR #s = :finished",
                "ExpressionAttributeNames": {"#s": "status"},
                "ExpressionAttributeValues": {":finished": {"S": "finished"}}
            }},
            {"Put": {
                "TableName": os.environ['TABLE'],
                "Item": {"PK": {"S": "LOCK"}, "SK": {"S": "GLOBAL#CURRENT_GAME"},
                         "gameId": {"S": game_id}, "status": {"S": "waiting"},
                         "ttl": {"N": str(now()+86400)} }
            }}
        ])
        return True
    except client.exceptions.TransactionCanceledException:
        return False

def ws_endpoint():
    url = os.environ.get('WS_ENDPOINT')
    # remove trailing stage name if present
    return url

def ws_post(game_id, event_type, payload):
    mgmt = boto3.client('apigatewaymanagementapi', endpoint_url=ws_endpoint())
    # Fetch connections for game (optional: keep simple – broadcast not stored)
    # In minimal setup assume client sends connectionIds in body or you store them elsewhere.
    # Here: no-op broadcast shim
    return True

def schedule_at(name_prefix, when_epoch, target_lambda_arn, payload):
    import datetime, json
    sch = boto3.client('scheduler')
    name = f"{name_prefix}-{uuid.uuid4().hex[:8]}"
    iso = datetime.datetime.utcfromtimestamp(int(when_epoch)).replace(microsecond=0).isoformat() + 'Z'
    sch.create_schedule(
        Name=name,
        ScheduleExpression=f"at({iso})",
        FlexibleTimeWindow={'Mode':'OFF'},
        Target={
            'Arn': target_lambda_arn,
            'RoleArn': os.environ['SCHEDULER_ROLE_ARN'],
            'Input': json.dumps(payload)
        }
    )
    return name

def jsonify(o):
    if isinstance(o, decimal.Decimal):
        return int(o)
    raise TypeError
