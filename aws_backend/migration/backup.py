#!/usr/bin/env python3
"""
Step 1: Export all data from old DynamoDB tables and list S3 objects.

Run BEFORE deploying new Terraform. Writes JSON backup files to this directory.

Usage:
    AWS_PROFILE=<profile> python3 backup.py [--workspace vereins-app-beta]
"""
import argparse
import json
import os
import sys
import boto3

REGION = 'eu-central-1'


def scan_table(table):
    items = []
    response = table.scan()
    items.extend(response.get('Items', []))
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))
    return items


def list_s3_objects(s3, bucket, prefix=''):
    objects = []
    kwargs = {'Bucket': bucket}
    if prefix:
        kwargs['Prefix'] = prefix
    response = s3.list_objects_v2(**kwargs)
    objects.extend(response.get('Contents', []))
    while response.get('IsTruncated'):
        response = s3.list_objects_v2(**kwargs, ContinuationToken=response['NextContinuationToken'])
        objects.extend(response.get('Contents', []))
    return [{'Key': o['Key'], 'Size': o['Size']} for o in objects]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', default='vereins-app-beta',
                        help='Terraform workspace (= DynamoDB table name prefix)')
    args = parser.parse_args()

    ws = args.workspace
    script_dir = os.path.dirname(os.path.abspath(__file__))

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    s3 = boto3.client('s3', region_name=REGION)

    # Resolve S3 bucket name from SSM or from the Lambda env (approximation)
    # Bucket follows the pattern <workspace>-<suffix>; list and pick the right one
    buckets = [b['Name'] for b in s3.list_buckets()['Buckets'] if b['Name'].startswith(ws)]
    if len(buckets) != 1:
        print(f'❌ Expected exactly 1 bucket starting with "{ws}", found: {buckets}')
        print('   Set S3_BUCKET env variable to override.')
        bucket = os.environ.get('S3_BUCKET')
        if not bucket:
            sys.exit(1)
    else:
        bucket = buckets[0]
    print(f'✅ S3 bucket: {bucket}')

    tables = {
        'members':         dynamodb.Table(f'{ws}-members'),
        'fines':           dynamodb.Table(f'{ws}-fines'),
        'marschbefehl':    dynamodb.Table(f'{ws}-marschbefehl'),
        'customers':       dynamodb.Table(f'vereinsappell-customers'),
        'reminders_sent':  dynamodb.Table(f'{ws}-reminders_sent'),
    }

    for name, table in tables.items():
        print(f'📦 Scanning {table.name} …', end=' ', flush=True)
        items = scan_table(table)
        out_path = os.path.join(script_dir, f'backup_{name}.json')
        with open(out_path, 'w') as f:
            json.dump(items, f, indent=2, default=str)
        print(f'{len(items)} items → {out_path}')

    print(f'📦 Listing S3 objects in {bucket} …', end=' ', flush=True)
    objects = list_s3_objects(s3, bucket)
    out_path = os.path.join(script_dir, 'backup_s3_objects.json')
    with open(out_path, 'w') as f:
        json.dump({'bucket': bucket, 'objects': objects}, f, indent=2)
    print(f'{len(objects)} objects → {out_path}')

    print('\n✅ Backup complete. Now run:')
    print('   1. terraform apply   (recreates tables with new schema)')
    print('   2. python3 restore.py')
    print('   3. python3 migrate_s3.py')


if __name__ == '__main__':
    main()
