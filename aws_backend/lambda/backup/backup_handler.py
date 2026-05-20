import decimal
import json
import os
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

BACKUP_BUCKET = os.environ.get('BACKUP_BUCKET', '')
TABLES = {
    'customers': os.environ.get('CUSTOMERS_TABLE_NAME', ''),
    'members': os.environ.get('MEMBERS_TABLE_NAME', ''),
    'marschbefehl': os.environ.get('MARSCHBEFEHL_TABLE_NAME', ''),
    'fines': os.environ.get('FINES_TABLE_NAME', ''),
}
MEMBERS_TABLE_NAME = os.environ.get('MEMBERS_TABLE_NAME', '')


def _serialize_decimal(obj):
    if isinstance(obj, decimal.Decimal):
        return int(obj) if obj == obj.to_integral_value() else float(obj)
    raise TypeError(f'Object of type {type(obj)} is not JSON serializable')


def lambda_handler(event, context):
    if event.get('source') == 'aws.events':
        return _run_backup()

    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    hdrs = event.get('headers', {})

    if not _is_superadmin(hdrs):
        return {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}

    if method == 'POST' and path == '/admin/backup':
        return _run_backup()
    if method == 'GET' and path == '/admin/backups':
        return _list_backups()

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


def _run_backup():
    now = datetime.now(ZoneInfo('Europe/Berlin'))
    timestamp = now.strftime('%Y-%m-%d_%H-%M')
    failed = []

    for name, table_name in TABLES.items():
        try:
            items = _scan_all(table_name)
            s3.put_object(
                Bucket=BACKUP_BUCKET,
                Key=f'dynamodb/{timestamp}/{name}.json',
                Body=json.dumps(items, default=_serialize_decimal),
                ContentType='application/json',
            )
        except Exception as e:
            print(f'Failed to backup {name}: {e}')
            failed.append(name)

    suffix = '-partial' if failed else ''
    return {
        'statusCode': 200,
        'body': json.dumps({
            's3_path': f's3://{BACKUP_BUCKET}/dynamodb/{timestamp}{suffix}/',
            'timestamp': timestamp,
            'failed': failed,
        }),
    }


def _scan_all(table_name):
    table = dynamodb.Table(table_name)
    items = []
    response = table.scan()
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    return items


def _list_backups():
    response = s3.list_objects_v2(
        Bucket=BACKUP_BUCKET,
        Prefix='dynamodb/',
        Delimiter='/',
    )
    timestamps = [
        p['Prefix'].removeprefix('dynamodb/').rstrip('/')
        for p in response.get('CommonPrefixes', [])
    ]
    timestamps.sort(reverse=True)
    return {'statusCode': 200, 'body': json.dumps({'backups': timestamps})}
