import base64
import json
import os
import urllib.parse
import boto3
import re

s3 = boto3.client('s3')
s3_bucket_name = os.environ.get('S3_BUCKET_NAME')

DOCS_PASSWORD = os.environ.get('DOCS_PASSWORD', 'geheim123')

_VALID_DOC_NAME = re.compile(r'^[A-Za-z0-9._\-/]+$')


def _is_valid_doc_name(name: str) -> bool:
    if not name or not _VALID_DOC_NAME.match(name):
        return False
    if '..' in name.split('/'):
        return False
    return True


def handle_docs(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    application_id = event.get('headers', {}).get('applicationid', '')
    prefix = f'{application_id}/docs'

    if method == 'GET' and path == '/docs':
        return _add_headers(get_docs(event, prefix), event=event)
    elif method == 'GET' and path.startswith('/docs/'):
        return _add_headers(get_doc(event, prefix), event=event)
    elif method == 'POST' and path.startswith('/docs'):
        return _add_headers(add_doc(event, prefix), event=event)
    elif method == 'DELETE' and path.startswith('/docs/'):
        return _add_headers(delete_doc(event, prefix), event=event)


def _add_headers(response, more_fields={}, event=None):
    origin = (event or {}).get('headers', {}).get('origin', 'https://vereinsappell.web.app')
    response_headers = {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Headers': 'Content-Type,applicationId,memberId,password',
        'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE',
    }
    return {**response_headers, **response, **more_fields}


def _unauthorized():
    return {
        'statusCode': 401,
        'body': json.dumps({'error': 'Unauthorized'}),
        'headers': {
            'Access-Control-Allow-Origin': 'https://vereinsappell.web.app',
            'Access-Control-Allow-Headers': 'Content-Type,applicationId,memberId,password',
            'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE',
        },
    }


def _check_password(event):
    headers = event.get('headers') or {}
    return headers.get('password') == DOCS_PASSWORD


def get_docs(event, prefix: str):
    if not _check_password(event):
        return _unauthorized()

    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=f'{prefix}/')
    contents = response.get('Contents', [])
    files = [{'name': obj['Key'].removeprefix(f'{prefix}/')} for obj in contents]
    return {
        'statusCode': 200,
        'body': json.dumps(files),
        'headers': {
            'Access-Control-Allow-Origin': 'https://vereinsappell.web.app',
            'Content-Type': 'application/json',
        },
    }


def get_doc(event, prefix: str):
    if not _check_password(event):
        return _unauthorized()

    file_name = urllib.parse.unquote(event['pathParameters']['fileName'])
    key = f'{prefix}/{file_name}'

    try:
        response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    except s3.exceptions.ClientError:
        return {'statusCode': 404, 'body': json.dumps({'error': 'Datei nicht gefunden'})}

    file_bytes = response['Body'].read()
    content_type = response.get('ContentType', 'application/octet-stream')
    return {
        'statusCode': 200,
        'isBase64Encoded': True,
        'headers': {
            'Content-Type': content_type,
            'Content-Disposition': f'inline; filename="{file_name}"',
            'Access-Control-Allow-Origin': 'https://vereinsappell.web.app',
        },
        'body': base64.b64encode(file_bytes).decode('utf-8'),
    }


def add_doc(event, prefix: str):
    if not _check_password(event):
        return _unauthorized()

    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    name = data['name']
    if not _is_valid_doc_name(name):
        return {'statusCode': 400, 'body': json.dumps({'error': 'Ungültiger Dateiname'})}

    key = f'{prefix}/{name}'
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return {'statusCode': 409, 'body': json.dumps({'error': 'Datei existiert bereits'})}
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] != '404':
            raise

    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=base64.b64decode(data['file']))
    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'{name} erfolgreich hochgeladen'}),
        'headers': {'Access-Control-Allow-Origin': 'https://vereinsappell.web.app'},
    }


def delete_doc(event, prefix: str):
    if not _check_password(event):
        return _unauthorized()

    file_name = urllib.parse.unquote(event['pathParameters']['fileName'])
    s3.delete_object(Bucket=s3_bucket_name, Key=f'{prefix}/{file_name}')
    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'{file_name} gelöscht'}),
        'headers': {'Access-Control-Allow-Origin': 'https://vereinsappell.web.app'},
    }
