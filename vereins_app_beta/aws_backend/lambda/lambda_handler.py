import json
import os
import boto3
import uuid
from boto3.dynamodb.conditions import Key
from datetime import datetime


dynamodb = boto3.resource('dynamodb')
members_table_name = os.environ.get('MEMBERS_TABLE_NAME')
fines_table_name = os.environ.get('FINES_TABLE_NAME')
marschbefehl_table_name = os.environ.get('MARSCHBEFEHL_TABLE_NAME')
members_table = dynamodb.Table(members_table_name)
fines_table = dynamodb.Table(fines_table_name)
marschbefehl_table = dynamodb.Table(marschbefehl_table_name)

def lambda_handler(event, context):
    try:
        method = event.get('requestContext', {}).get('http', {}).get('method')
        path = event.get('requestContext', {}).get('http', {}).get('path')

        if method == 'GET' and path == '/members':
            return get_members(event)
        elif method == 'GET' and path.startswith('/members/'):
            return get_member_by_id(event)
        elif method == 'POST' and path == '/members':
            return add_member(event)
        elif method == 'DELETE' and path.startswith('/members/'):
            return delete_member(event)
        elif method == 'GET' and path == '/fines':
            return get_fines(event)
        elif method == 'POST' and path == '/fines':
            return add_fine(event)
        elif method == 'DELETE' and path.startswith('/fines/'):
            return delete_fine(event)
        elif method == 'GET' and path == '/marschbefehl':
            return get_marschbefehl(event)
        else:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Nicht gefunden', 'event': event})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'event': event})
        }


def get_member_by_id(event):
    try:
        member_id = event['pathParameters']['memberId']

        response = members_table.get_item(
            Key={'memberId': member_id}
        )

        item = response.get('Item')

        if not item:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Mitglied nicht gefunden'})
            }

        return {
            'statusCode': 200,
            'body': json.dumps(item)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'event': event})
        }

def get_members(event):
    items = []

    response = members_table.scan()
    items.extend(response['Items'])

    # Falls es mehr als 1MB Daten sind, wird die Scan-Operation paginiert
    while 'LastEvaluatedKey' in response:
        response = members_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }


def add_member(event):
    try:
        data = json.loads(event['body'])
        member_id = data['memberId']
        name = data['name']
        is_admin = data.get('isAdmin', False)
        is_spiess = data.get('isSpiess', False)

        item = {
            'memberId': member_id,
            'name': name,
            'isAdmin': is_admin,
            'isSpiess': is_spiess
        }

        members_table.put_item(Item=item)

        return {
            'statusCode': 200,
            'body': json.dumps(item)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def delete_member(event):
    try:
        member_id = event['pathParameters']['memberId']

        members_table.delete_item(
            Key={'memberId': member_id}
        )

        return {'statusCode': 200, 'body': json.dumps({'message': 'Mitglied gelöscht'})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(event)})}



def get_fines(event):
    params = event.get('queryStringParameters') or {}
    member_id = params.get('memberId')
    name = member_id

    if not member_id:
        return {'statusCode': 400, 'body': json.dumps({'error': 'memberId fehlt'})}

    member_response = members_table.query(
        KeyConditionExpression=Key('memberId').eq(member_id)
    )
    member = member_response.get('Items', [])
    # member should have one elem
    if member:
        member = member[0]
        name = member.get('name', member_id)


    fines_response = fines_table.query(
        KeyConditionExpression=Key('memberId').eq(member_id)
    )
    items = fines_response.get('Items', [])
    import decimal
    class DecimalEncoder(json.JSONEncoder):
        def default(self, o):
            if isinstance(o, decimal.Decimal):
                return str(o)
            return super(DecimalEncoder, self).default(o)

    return {
        'statusCode': 200,
        'body': json.dumps({"name": name, "fines": items}, cls=DecimalEncoder)
    }


def add_fine(event):
    try:
        data = json.loads(event['body'])
        member_id = data['memberId']
        reason = data['reason']
        amount = data['amount']

        fine_id = str(uuid.uuid4())

        item = {
            'app-memberId-fineId': member_id,
            'memberId': member_id,
            'fineId': fine_id,
            'reason': reason,
            'amount': amount,
        }

        fines_table.put_item(Item=item)

        # Beispielhafte Push-Nachricht
        print(f'Push: Neue Strafe für {member_id}: {reason} ({amount} €)')

        return {
            'statusCode': 200,
            'body': json.dumps(item)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def delete_fine(event):
    try:
        fine_id = event['pathParameters']['fineId']
        member_id = event['queryStringParameters']['memberId']

        fines_table.delete_item(
            Key={'memberId': member_id, 'fineId': fine_id}
        )

        return {'statusCode': 200, 'body': json.dumps({'message': 'Strafe gelöscht'})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}


def get_marschbefehl(event):
    now = datetime.now()
    datetimestamp = now.strftime("%Y-%m-%d %H:%M")

    items = []
    query_filter = Key('type').eq('marschbefehl') & Key('datetime').gte(datetimestamp)
    response = marschbefehl_table.query(
        KeyConditionExpression=query_filter,
    )

    items.extend(response['Items'])

    # Falls es mehr als 1MB Daten sind, wird die Scan-Operation paginiert
    while 'LastEvaluatedKey' in response:
        response = marschbefehl_table.query(
            KeyConditionExpression=query_filter,
            ExclusiveStartKey=response['LastEvaluatedKey'],
        )
        items.extend(response['Items'])

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }
