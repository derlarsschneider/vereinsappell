#!/usr/bin/env python3
# scripts/backup_restore.py
"""
Usage:
  python scripts/backup_restore.py backup
  python scripts/backup_restore.py list
  python scripts/backup_restore.py restore 2026-05-11_02-00
  python scripts/backup_restore.py clear members
"""
import json
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3

BACKUP_BUCKET = 'vereinsappell-backups'
TABLES = {
    'customers': 'vereinsappell-customers',
    'members': 'vereins-app-beta-members',
    'marschbefehl': 'vereins-app-beta-marschbefehl',
    'fines': 'vereins-app-beta-fines',
}
TABLE_KEYS = {
    'customers': ['application_id'],
    'members': ['applicationId', 'memberId'],
    'marschbefehl': ['applicationId', 'datetime'],
    'fines': ['applicationId', 'fineId'],
}

dynamodb = boto3.resource('dynamodb', region_name='eu-central-1')
s3 = boto3.client('s3', region_name='eu-central-1')


def cmd_backup():
    now = datetime.now(ZoneInfo('Europe/Berlin'))
    timestamp = now.strftime('%Y-%m-%d_%H-%M')
    failed = []

    for name, table_name in TABLES.items():
        try:
            items = _scan_all(table_name)
            s3.put_object(
                Bucket=BACKUP_BUCKET,
                Key=f'dynamodb/{timestamp}/{name}.json',
                Body=json.dumps(items, default=str),
                ContentType='application/json',
            )
            print(f'  ✓ {name}: {len(items)} items')
        except Exception as e:
            print(f'  ✗ {name}: {e}')
            failed.append(name)

    suffix = ' (partial)' if failed else ''
    print(f'\nBackup saved: s3://{BACKUP_BUCKET}/dynamodb/{timestamp}/{suffix}')
    if failed:
        sys.exit(1)


def cmd_list():
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
    if not timestamps:
        print('No backups found.')
        return
    for ts in timestamps:
        print(ts)


def cmd_restore(timestamp):
    prefix = f'dynamodb/{timestamp}/'
    check = s3.list_objects_v2(Bucket=BACKUP_BUCKET, Prefix=prefix)
    if not check.get('Contents'):
        print(f'Backup {timestamp} not found in S3.')
        sys.exit(1)

    print(f'Restoring from {timestamp}...')
    failed = []
    for name, table_name in TABLES.items():
        key = f'{prefix}{name}.json'
        try:
            obj = s3.get_object(Bucket=BACKUP_BUCKET, Key=key)
            items = json.loads(obj['Body'].read())
            table = dynamodb.Table(table_name)
            with table.batch_writer() as batch:
                for item in items:
                    batch.put_item(Item=item)
            print(f'  ✓ {name}: {len(items)} items written')
        except Exception as e:
            print(f'  ✗ {name}: {e}')
            failed.append(name)

    print('Done.')
    if failed:
        sys.exit(1)


def cmd_clear(table_key):
    if table_key not in TABLES:
        print(f'Unknown table: {table_key}. Choose from: {", ".join(TABLES)}')
        sys.exit(1)

    table_name = TABLES[table_key]
    keys = TABLE_KEYS[table_key]
    table = dynamodb.Table(table_name)

    confirm = input(f'Delete ALL items from {table_key} ({table_name})? Type "yes" to confirm: ')
    if confirm.strip() != 'yes':
        print('Aborted.')
        return

    items = _scan_all(table_name)
    with table.batch_writer() as batch:
        for item in items:
            batch.delete_item(Key={k: item[k] for k in keys})

    print(f'Deleted {len(items)} items from {table_key}.')


def _scan_all(table_name):
    table = dynamodb.Table(table_name)
    items = []
    response = table.scan()
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    return items


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]
    if command == 'backup':
        cmd_backup()
    elif command == 'list':
        cmd_list()
    elif command == 'restore':
        if len(sys.argv) < 3:
            print('Usage: backup_restore.py restore <timestamp>')
            sys.exit(1)
        cmd_restore(sys.argv[2])
    elif command == 'clear':
        if len(sys.argv) < 3:
            print('Usage: backup_restore.py clear <table>')
            sys.exit(1)
        cmd_clear(sys.argv[2])
    else:
        print(f'Unknown command: {command}')
        print(__doc__)
        sys.exit(1)
