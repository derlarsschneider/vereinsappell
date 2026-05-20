import decimal
import json
import os

import boto3
import firebase_backup

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

BACKUP_BUCKET = os.environ.get('BACKUP_BUCKET', '')
FIREBASE_SECRET_NAME = os.environ.get('FIREBASE_SECRET_NAME', '')
FIREBASE_DATABASE_URL = os.environ.get('FIREBASE_DATABASE_URL', '')
TABLES = {
    'customers': os.environ.get('CUSTOMERS_TABLE_NAME', ''),
    'members': os.environ.get('MEMBERS_TABLE_NAME', ''),
    'marschbefehl': os.environ.get('MARSCHBEFEHL_TABLE_NAME', ''),
    'fines': os.environ.get('FINES_TABLE_NAME', ''),
}
MEMBERS_TABLE_NAME = os.environ.get('MEMBERS_TABLE_NAME', '')

# Primary key attribute names per logical table name
TABLE_KEYS = {
    'customers': ['application_id'],
    'members': ['applicationId', 'memberId'],
    'marschbefehl': ['applicationId', 'datetime'],
    'fines': ['applicationId', 'fineId'],
}


def lambda_handler(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    hdrs = event.get('headers', {})
    params = event.get('pathParameters') or {}

    if not _is_superadmin(hdrs):
        return {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}

    if method == 'POST' and path.endswith('/restore'):
        timestamp = params.get('timestamp', '')
        return _restore(timestamp)
    if method == 'DELETE' and path.endswith('/items'):
        table_name_key = params.get('tableName', '')
        return _clear_table(table_name_key)

    return {'statusCode': 404, 'body': json.dumps({'error': 'Nicht gefunden'})}


def _is_superadmin(hdrs):
    application_id = hdrs.get('applicationid', '')
    member_id = hdrs.get('memberid', '')
    if not application_id or not member_id:
        return False
    table = dynamodb.Table(MEMBERS_TABLE_NAME)
    item = table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def _restore(timestamp):
    prefix = f'dynamodb/{timestamp}/'
    check = s3.list_objects_v2(Bucket=BACKUP_BUCKET, Prefix=prefix)
    if not check.get('Contents'):
        return {'statusCode': 404, 'body': json.dumps({'error': f'Backup {timestamp} nicht gefunden'})}

    restored = []
    failed = []
    for name, table_name in TABLES.items():
        key = f'{prefix}{name}.json'
        try:
            obj = s3.get_object(Bucket=BACKUP_BUCKET, Key=key)
            items = json.loads(obj['Body'].read(), parse_float=decimal.Decimal, parse_int=decimal.Decimal)
            _batch_write(table_name, items)
            restored.append(name)
        except Exception as e:
            print(f'Failed to restore {name}: {e}')
            failed.append({'table': name, 'error': str(e)})

    try:
        firebase_backup.restore_polls(FIREBASE_DATABASE_URL, FIREBASE_SECRET_NAME, s3, BACKUP_BUCKET, timestamp)
        restored.append('firebase/polls')
    except Exception as e:
        print(f'Failed to restore firebase/polls: {e}')
        failed.append({'table': 'firebase/polls', 'error': str(e)})

    return {
        'statusCode': 200,
        'body': json.dumps({'restored': restored, 'failed': failed}),
    }


def _batch_write(table_name, items):
    table = dynamodb.Table(table_name)
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)


def _clear_table(table_name_key):
    if table_name_key not in TABLES:
        return {'statusCode': 400, 'body': json.dumps({'error': f'Unbekannte Tabelle: {table_name_key}'})}

    table_name = TABLES[table_name_key]
    table = dynamodb.Table(table_name)
    keys = TABLE_KEYS[table_name_key]

    items = []
    response = table.scan()
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])

    with table.batch_writer() as batch:
        for item in items:
            batch.delete_item(Key={k: item[k] for k in keys})

    return {
        'statusCode': 200,
        'body': json.dumps({'deleted': len(items), 'table': table_name_key}),
    }
