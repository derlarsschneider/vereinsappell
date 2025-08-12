import base64
import json
import os
import uuid
from datetime import datetime

import boto3
from boto3.dynamodb.conditions import Key
from push_notifications import send_push_notification
import error_handler

from api_members import handle_members

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
        headers = {
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
        }

        if method == 'OPTIONS':
            return {
                "statusCode": 204,
                "headers": headers,
            }
        elif path.startswith('/members'):
            return handle_members(event, context)
        elif method == 'GET' and path == '/fines':
            return {**headers, **get_fines(event)}
        elif method == 'POST' and path == '/fines':
            return {**headers, **add_fine(event)}
        elif method == 'DELETE' and path.startswith('/fines/'):
            return {**headers, **delete_fine(event)}
        elif method == 'GET' and path == '/marschbefehl':
            return {**headers, **get_marschbefehl(event)}
        elif method == 'GET' and path.startswith('/photos'):
            return {**headers, **get_docs(event, f'photos')}
        elif method == 'POST' and path.startswith('/photos'):
            return {**headers, **add_docs(event, 'photos')}
        elif method == 'GET' and path.startswith('/docs/'):
            return {**headers, **get_doc(event)}
        elif method == 'GET' and path == '/docs':
            return {**headers, **get_docs(event)}
        elif method == 'POST' and path.startswith('/docs'):
            return {**headers, **add_docs(event)}
        elif method == 'DELETE' and path.startswith('/docs'):
            return {**headers, **delete_doc(event)}
        elif method == 'GET' and path.startswith('/customers/'):
            import api_customers
            return {**headers, **api_customers.get_customer_by_id(event, context)}
        elif method == 'GET' and path.startswith('/calendar'):
            import api_calendar
            return {**headers, **api_calendar.get_calendar(event, context)}
        else:
            error_handler.handle_error(event, context)
            print(f'❌ Unknown API route: {method} {path}')
            print(json.dumps({'error': 'Nicht gefunden', 'event': event}))
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Nicht gefunden'})
            }
    except Exception as exception:
        error_handler.handle_error(event, context, exception)
        print(f'❌ Exception in lambda_handler')
        print(json.dumps({'error': str(exception), 'event': event}))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(exception)})
        }

def message_response(status_code: int, message: str):
    return {
        "statusCode": status_code,
        "body": json.dumps({"message": message})
    }

def delete_doc(event, prefix: str = 'docs'):
    file_name = event['pathParameters']['fileName']
    file_name = urllib.parse.unquote(file_name)
    key = f'{prefix}/{file_name}'
    s3 = boto3.client('s3')
    s3.delete_object(Bucket=s3_bucket_name, Key=key)
    return {"statusCode": 200, "body": f"Datei ${key} gelöscht"}


def add_docs(event, prefix: str = 'docs'):
    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    name = data['name']
    file_base64 = data['file']
    key = f'{prefix}/{name}'
    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return message_response(409, "Datei existiert bereits")
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] != '404':
            raise

    body = base64.b64decode(file_base64)
    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=body)
    return message_response(200, str(body))


def get_docs(event, prefix: str = 'docs'):
    proxy = event.get('pathParameters', {}).get('proxy')
    if proxy is not None:
        prefix = f'{prefix}/{proxy}'
    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=f'{prefix}')
        response = s3.get_object(Bucket=s3_bucket_name, Key=f'{prefix}')
        file_bytes = response['Body'].read()

        # Optional: Content-Type erkennen (hier: aus den S3-Metadaten oder per Dateiendung schätzen)
        content_type = response.get('ContentType', 'application/octet-stream')

        return {
            'statusCode': 200,
            'isBase64Encoded': True,
            'headers': {
                'Content-Type': content_type,
                'Content-Disposition': f'inline; filename="{proxy}"',
                'Access-Control-Allow-Origin': '*',
            },
            'body': base64.b64encode(file_bytes).decode('utf-8'),
        }
    except s3.exceptions.ClientError as e:
        files = list_s3_files(prefix)
        body = json.dumps(files)
        return {"statusCode": 200, "body": body}


def list_s3_files(prefix):
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=f'{prefix}/', )
    files = [{
        "name": obj['Key'].removeprefix(f'{prefix}/'),
        "file": get_s3_content(obj['Key']) if prefix.endswith('thumbnails') else ''
    } for obj in response.get('Contents', [])]

    return files


def get_s3_content(key):
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    file_bytes = response['Body'].read()
    return base64.b64encode(file_bytes).decode('utf-8')

import urllib.parse

def get_doc(event, prefix: str = 'docs'):
    s3 = boto3.client('s3')
    file_name = event['pathParameters']['fileName']
    file_name = urllib.parse.unquote(file_name)
    key = f'{prefix}/{file_name}'

    response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    file_bytes = response['Body'].read()

    # Optional: Content-Type erkennen (hier: aus den S3-Metadaten oder per Dateiendung schätzen)
    content_type = response.get('ContentType', 'application/octet-stream')

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
    # 📲 Token aus DynamoDB holen
    response = members_table.get_item(Key={'memberId': member_id})
    name = response.get("Item", {}).get("name")
    token = response.get("Item", {}).get("token")

    if token:
        push_response = send_push_notification(
            token=token,
            notification={
                'title': f'Neue Strafe für {name}',
                'body': f'{reason} ({amount} €)',
                'url': '/strafen'
            },
            secret_name='firebase-credentials'  # Name im Secrets Manager
        )
        item['pushResponse'] = push_response

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }


def delete_fine(event):
    fine_id = event['pathParameters']['fineId']
    member_id = event['queryStringParameters']['memberId']

    fines_table.delete_item(
        Key={'memberId': member_id, 'fineId': fine_id}
    )

    return {'statusCode': 200, 'body': json.dumps({'message': 'Strafe gelöscht'})}


def get_marschbefehl(event):
    now = datetime.now()
    datetimestamp = now.strftime("%Y-%m-%d")

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


def get_photos(event):
    prefix = 'photos/'
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=prefix)
    items = response.get('Contents', [])

    photo_urls = []
    for item in items:
        key = item['Key']
        if key.endswith('.jpg') or key.endswith('.jpeg') or key.endswith('.png'):
            url = s3.generate_presigned_url(
                ClientMethod='get_object',
                Params={'Bucket': s3_bucket_name, 'Key': key},
                ExpiresIn=900  # URL 15 Minuten gültig
            )
            photo_urls.append({
                'key': key,
                'url': url
            })

    return _response(200, photo_urls)


def post_photo(event):
    body = event.get('body')
    if not body:
        return _response(400, 'Kein Inhalt')

    data = json.loads(body)
    image_base64 = data.get('imageBase64')

    if not image_base64:
        return _response(400, 'Kein Bild enthalten')

    image_bytes = base64.b64decode(image_base64)
    image_id = str(uuid.uuid4())
    s3_key = f'photos/{image_id}.jpg'

    s3 = boto3.client('s3')
    s3.put_object(
        Bucket=s3_bucket_name,
        Key=s3_key,
        Body=image_bytes,
        ContentType='image/jpeg',
    )

    image_url = f'https://{s3_bucket_name}.s3.amazonaws.com/{s3_key}'
    return _response(200, {
        'id': image_id,
        'url': image_url
    })


def _response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body)
    }
