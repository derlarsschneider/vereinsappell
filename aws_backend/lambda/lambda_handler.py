import base64
import decimal
import json
import os
import uuid
from datetime import datetime

import boto3
from boto3.dynamodb.conditions import Key, Attr
from push_notifications import send_push_notification


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, decimal.Decimal):
            return str(o)
        return super().default(o)


import error_handler

from api_members import handle_members
from api_docs import handle_docs

dynamodb = boto3.resource('dynamodb')

members_table_name = os.environ.get('MEMBERS_TABLE_NAME')
fines_table_name = os.environ.get('FINES_TABLE_NAME')
marschbefehl_table_name = os.environ.get('MARSCHBEFEHL_TABLE_NAME')
members_table = dynamodb.Table(members_table_name)
fines_table = dynamodb.Table(fines_table_name)
marschbefehl_table = dynamodb.Table(marschbefehl_table_name)
s3_bucket_name = os.environ.get('S3_BUCKET_NAME')


def lambda_handler(event, context):
    try:
        method = event.get('requestContext', {}).get('http', {}).get('method')
        path = event.get('requestContext', {}).get('http', {}).get('path')
        origin = event.get('headers', {}).get('origin', 'https://vereinsappell.web.app')
        application_id = event.get('headers', {}).get('applicationid', '')
        member_id = event.get('headers', {}).get('memberid', '')

        # Structured logging for API monitoring
        print(json.dumps({
            "log_type": "api_access",
            "applicationId": application_id,
            "memberId": member_id,
            "path": path,
            "httpMethod": method,
            "timestamp": datetime.now().isoformat()
        }))

        headers = {
            'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Headers': 'Content-Type,applicationId,memberId,password',
            'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE,PUT',
        }

        if method == 'OPTIONS':
            return {'statusCode': 204, 'headers': headers}
        elif path.startswith('/members'):
            return handle_members(event, context)
        elif path.startswith('/docs'):
            return handle_docs(event, context)
        elif method == 'GET' and path == '/fines':
            return {**headers, **get_fines(event, application_id)}
        elif method == 'POST' and path == '/fines':
            return {**headers, **add_fine(event, application_id)}
        elif method == 'DELETE' and path.startswith('/fines/'):
            return {**headers, **delete_fine(event, application_id)}
        elif method == 'GET' and path == '/marschbefehl':
            return {**headers, **get_marschbefehl(event, application_id)}
        elif method == 'POST' and path == '/marschbefehl':
            return {**headers, **add_marschbefehl(event, application_id)}
        elif method == 'DELETE' and path == '/marschbefehl':
            return {**headers, **delete_marschbefehl(event, application_id)}
        elif method == 'GET' and path.startswith('/photos'):
            return {**headers, **get_photos(event, application_id)}
        elif method == 'POST' and path.startswith('/photos'):
            return {**headers, **add_photo(event, application_id)}
        elif method == 'GET' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.get_customer_by_id(event, context)}
        elif method == 'GET' and path == '/customers':
            import api_customers
            return {**headers, **api_customers.list_customers()}
        elif method == 'POST' and path == '/customers':
            import api_customers
            return {**headers, **api_customers.create_customer(event)}
        elif method == 'PUT' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.update_customer(event)}
        elif method == 'GET' and path.startswith('/calendar'):
            import api_calendar
            return {**headers, **api_calendar.get_calendar(event, context)}
        elif method == 'GET' and path == '/monitoring/stats':
            import api_monitoring
            return {**headers, **api_monitoring.handle_monitoring(event, context)}
        elif method == 'POST' and path == '/monitoring/timing':
            import api_monitoring
            return {**headers, **api_monitoring.handle_timing(event, context)}
        elif method == 'GET' and path == '/monitoring/startup':
            import api_monitoring
            return {**headers, **api_monitoring.handle_startup_stats(event, context)}
        else:
            error_handler.handle_error(event, context)
            print(f'❌ Unknown API route: {method} {path}')
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Nicht gefunden'})
            }
    except Exception as exception:
        error_handler.handle_error(event, context, exception)
        print(f'❌ Exception in lambda_handler: {exception}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(exception)})
        }


def get_fines(event, application_id):
    params = event.get('queryStringParameters') or {}
    member_id = params.get('memberId')

    if not member_id:
        return {'statusCode': 400, 'body': json.dumps({'error': 'memberId fehlt'})}

    member = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    name = member.get('name', member_id) if member else member_id

    fines_response = fines_table.query(
        KeyConditionExpression=Key('applicationId').eq(application_id),
        FilterExpression=Attr('memberId').eq(member_id),
    )
    items = fines_response.get('Items', [])
    while 'LastEvaluatedKey' in fines_response:
        fines_response = fines_table.query(
            KeyConditionExpression=Key('applicationId').eq(application_id),
            FilterExpression=Attr('memberId').eq(member_id),
            ExclusiveStartKey=fines_response['LastEvaluatedKey'],
        )
        items.extend(fines_response.get('Items', []))

    return {
        'statusCode': 200,
        'body': json.dumps({'name': name, 'fines': items}, cls=DecimalEncoder)
    }


def add_fine(event, application_id):
    data = json.loads(event['body'])
    member_id = data['memberId']
    reason = data['reason']
    amount = data['amount']
    fine_id = str(uuid.uuid4())

    item = {
        'applicationId': application_id,
        'memberId': member_id,
        'fineId': fine_id,
        'reason': reason,
        'amount': amount,
    }
    fines_table.put_item(Item=item)

    member_item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item', {})
    name = member_item.get('name')
    token = member_item.get('token')

    if token:
        push_response = send_push_notification(
            token=token,
            notification={
                'title': f'Neue Strafe für {name}',
                'body': f'{reason} ({amount} €)',
                'url': '/strafen',
                'type': 'fine',
            },
            secret_name='firebase-credentials'
        )
        item['pushResponse'] = push_response

    return {'statusCode': 200, 'body': json.dumps(item)}


def delete_fine(event, application_id):
    fine_id = event['pathParameters']['fineId']
    fines_table.delete_item(
        Key={'applicationId': application_id, 'fineId': fine_id}
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Strafe gelöscht'})}


def get_marschbefehl(event, application_id):
    now = datetime.now()
    datetimestamp = now.strftime('%Y-%m-%d')

    items = []
    query_filter = Key('applicationId').eq(application_id) & Key('datetime').gte(datetimestamp)
    response = marschbefehl_table.query(KeyConditionExpression=query_filter)
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = marschbefehl_table.query(
            KeyConditionExpression=query_filter,
            ExclusiveStartKey=response['LastEvaluatedKey'],
        )
        items.extend(response['Items'])

    return {'statusCode': 200, 'body': json.dumps(items)}


def add_marschbefehl(event, application_id):
    data = json.loads(event['body'])
    item = {
        'applicationId': application_id,
        'datetime': data['datetime'],
        'text': data['text'],
    }
    marschbefehl_table.put_item(Item=item)
    return {'statusCode': 200, 'body': json.dumps({'message': 'Marschbefehl gespeichert'})}


def delete_marschbefehl(event, application_id):
    params = event.get('queryStringParameters') or {}
    datetime_val = params.get('datetime')
    if not datetime_val:
        return {'statusCode': 400, 'body': json.dumps({'error': 'datetime fehlt'})}

    marschbefehl_table.delete_item(
        Key={'applicationId': application_id, 'datetime': datetime_val}
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Marschbefehl gelöscht'})}


def get_photos(event, application_id):
    import urllib.parse
    s3 = boto3.client('s3')
    proxy = (event.get('pathParameters') or {}).get('proxy')
    prefix = f'{application_id}/photos'
    if proxy:
        prefix = f'{prefix}/{urllib.parse.unquote(proxy)}'

    try:
        s3.head_object(Bucket=s3_bucket_name, Key=prefix)
        response = s3.get_object(Bucket=s3_bucket_name, Key=prefix)
        file_bytes = response['Body'].read()
        content_type = response.get('ContentType', 'application/octet-stream')
        file_name = prefix.split('/')[-1]
        return {
            'statusCode': 200,
            'isBase64Encoded': True,
            'headers': {
                'Content-Type': content_type,
                'Content-Disposition': f'inline; filename="{file_name}"',
                'Access-Control-Allow-Origin': '*',
            },
            'body': base64.b64encode(file_bytes).decode('utf-8'),
        }
    except Exception:
        response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=f'{prefix}/')
        files = [{
            'name': obj['Key'].removeprefix(f'{prefix}/'),
            'file': _get_s3_content(obj['Key']) if 'thumbnails' in prefix else '',
        } for obj in response.get('Contents', [])]
        return {'statusCode': 200, 'body': json.dumps(files)}


def add_photo(event, application_id):
    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    name = data['name']
    file_base64 = data['file']
    key = f'{application_id}/photos/{name}'
    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return {'statusCode': 409, 'body': json.dumps({'error': 'Datei existiert bereits'})}
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] != '404':
            raise
    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=base64.b64decode(file_base64))
    return {'statusCode': 200, 'body': json.dumps({'message': f'{name} hochgeladen'})}


def _get_s3_content(key):
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    return base64.b64encode(response['Body'].read()).decode('utf-8')


def message_response(status_code: int, message: str):
    return {
        'statusCode': status_code,
        'body': json.dumps({'message': message})
    }
