import base64
import json
import os
import time
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3
from boto3.dynamodb.conditions import Key, Attr
from push_notifications import send_push_notification
from utils import DecimalEncoder


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

_PERF_ENABLED = os.environ.get('PERF_LOGGING_ENABLED', '').lower() == 'true'


def lambda_handler(event, context):
    if event.get('source') == 'aws.events':
        return {'statusCode': 200}
    try:
        method = event.get('requestContext', {}).get('http', {}).get('method')
        path = event.get('requestContext', {}).get('http', {}).get('path')
        origin = event.get('headers', {}).get('origin', 'https://vereinsappell.web.app')
        application_id = event.get('headers', {}).get('applicationid', '')
        member_id = event.get('headers', {}).get('memberid', '')

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

        start = time.monotonic()
        result = _dispatch(event, context, method, path, application_id, headers)

        if result is not None:
            if _PERF_ENABLED:
                print(json.dumps({
                    "log_type": "perf_timing",
                    "path": path,
                    "method": method,
                    "applicationId": application_id,
                    "duration_ms": int((time.monotonic() - start) * 1000),
                }))
            return result

        error_handler.handle_error(event, context)
        print(f'❌ Unknown API route: {method} {path}')
        return {'statusCode': 404, 'body': json.dumps({'error': 'Nicht gefunden'})}
    except Exception as exception:
        error_handler.handle_error(event, context, exception)
        print(f'❌ Exception in lambda_handler: {exception}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(exception)})
        }


def _dispatch(event, context, method, path, application_id, headers):
    if path.startswith('/members'):
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
    elif method == 'DELETE' and path.startswith('/photos/'):
        return {**headers, **delete_photo(event, application_id)}
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
    elif method == 'GET' and path == '/monitoring/perf':
        import api_monitoring
        return {**headers, **api_monitoring.handle_perf_stats(event, context)}
    return None


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
    now = datetime.now(ZoneInfo("Europe/Berlin"))
    date = now.strftime("%Y-%m-%d %H:%M:%S")
    fine_id = str(uuid.uuid4())

    item = {
        'applicationId': application_id,
        'memberId': member_id,
        'fineId': fine_id,
        'reason': reason,
        'amount': amount,
        'date': date,
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

    if proxy and proxy != 'thumbnails':
        # Single file fetch — return presigned URL
        key = f'{application_id}/photos/{urllib.parse.unquote(proxy)}'
        url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': key},
            ExpiresIn=3600,
        )
        return {'statusCode': 200, 'body': json.dumps({'url': url})}

    # List thumbnails — return presigned URLs for both sizes
    thumb_prefix = f'{application_id}/photos/thumbnails/'
    img_prefix = f'{application_id}/photos/img/'
    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=thumb_prefix)
    files = []
    for obj in response.get('Contents', []):
        basename = obj['Key'].removeprefix(thumb_prefix)
        thumbnail_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': obj['Key']},
            ExpiresIn=3600,
        )
        photo_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': s3_bucket_name, 'Key': f'{img_prefix}{basename}'},
            ExpiresIn=3600,
        )
        files.append({'name': basename, 'thumbnail_url': thumbnail_url, 'photo_url': photo_url})
    return {'statusCode': 200, 'body': json.dumps(files)}


def add_photo(event, application_id):
    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    raw_name = data['name']
    basename = raw_name.split('/')[-1]
    stem = basename.rsplit('.', 1)[0] if '.' in basename else basename
    basename = stem.lower() + '.jpg'

    img_key = f'{application_id}/photos/img/{basename}'
    thumb_key = f'{application_id}/photos/thumbnails/{basename}'

    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=img_key)
        return {'statusCode': 409, 'body': json.dumps({'error': 'Datei existiert bereits'})}
    except Exception as e:
        if hasattr(e, 'response') and e.response.get('Error', {}).get('Code') != '404':
            raise

    image_bytes = base64.b64decode(data['file'])
    thumbnail_bytes = _generate_thumbnail(image_bytes)

    s3.put_object(Bucket=s3_bucket_name, Key=img_key, Body=image_bytes, ContentType='image/jpeg')
    s3.put_object(Bucket=s3_bucket_name, Key=thumb_key, Body=thumbnail_bytes, ContentType='image/jpeg')

    return {'statusCode': 200, 'body': json.dumps({'message': f'{basename} hochgeladen'})}


def delete_photo(event, application_id):
    import urllib.parse
    proxy = (event.get('pathParameters') or {}).get('proxy')
    if not proxy:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Dateiname fehlt'})}
    basename = urllib.parse.unquote(proxy)
    s3 = boto3.client('s3')
    s3.delete_object(Bucket=s3_bucket_name, Key=f'{application_id}/photos/img/{basename}')
    s3.delete_object(Bucket=s3_bucket_name, Key=f'{application_id}/photos/thumbnails/{basename}')
    return {'statusCode': 200, 'body': json.dumps({'message': f'{basename} gelöscht'})}


def _generate_thumbnail(image_bytes, size=400):
    from PIL import Image
    import io as _io
    img = Image.open(_io.BytesIO(image_bytes)).convert('RGB')
    w, h = img.size
    min_dim = min(w, h)
    left = (w - min_dim) // 2
    top = (h - min_dim) // 2
    img = img.crop((left, top, left + min_dim, top + min_dim))
    img = img.resize((size, size), Image.LANCZOS)
    buf = _io.BytesIO()
    img.save(buf, format='JPEG', quality=70)
    return buf.getvalue()


def message_response(status_code: int, message: str):
    return {
        'statusCode': status_code,
        'body': json.dumps({'message': message})
    }
