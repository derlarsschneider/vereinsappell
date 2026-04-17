#!/usr/bin/env python3
"""
Step 3: Copy S3 objects to new applicationId-prefixed paths.

Old layout:  docs/{name}           photos/{name}
New layout:  {appId}/docs/{name}   {appId}/photos/{name}

Objects that already contain a '/' in the first segment (= already migrated
or thumbnails sub-folder) are handled correctly by the prefix detection.

Only objects whose key starts with 'docs/' or 'photos/' are migrated.
Everything else is left untouched.

Usage:
    AWS_PROFILE=<profile> python3 migrate_s3.py [--workspace vereinsappell] [--application-id <id>] [--dry-run]
"""
import argparse
import json
import os
import sys
import boto3

REGION = 'eu-central-1'
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MIGRATABLE_PREFIXES = ('docs/', 'photos/')


def load_backup_s3():
    path = os.path.join(SCRIPT_DIR, 'backup_s3_objects.json')
    if not os.path.exists(path):
        print(f'❌ backup_s3_objects.json not found — run backup.py first')
        sys.exit(1)
    with open(path) as f:
        data = json.load(f)
    return data['bucket'], data['objects']


def needs_migration(key):
    return any(key.startswith(p) for p in MIGRATABLE_PREFIXES)


def new_key(old_key, application_id):
    # docs/foo.pdf → {appId}/docs/foo.pdf
    # photos/bar.jpg → {appId}/photos/bar.jpg
    return f'{application_id}/{old_key}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', default='vereinsappell')
    parser.add_argument('--application-id', default=None,
                        help='applicationId to use as S3 prefix (auto-detected if single club)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Print planned copies without executing them')
    args = parser.parse_args()

    bucket, objects = load_backup_s3()
    print(f'📦 Bucket: {bucket}  ({len(objects)} total objects)')

    application_id = args.application_id
    if not application_id:
        customers_path = os.path.join(SCRIPT_DIR, 'backup_customers.json')
        if os.path.exists(customers_path):
            with open(customers_path) as f:
                customers = json.load(f)
            ids = [c['application_id'] for c in customers]
            if len(ids) == 1:
                application_id = ids[0]
                print(f'📌 Single club detected — using applicationId={application_id}')
            else:
                print(f'❌ Multiple clubs: {ids}. Pass --application-id <id>.')
                sys.exit(1)
        else:
            print('❌ backup_customers.json not found and --application-id not set.')
            sys.exit(1)

    to_migrate = [o for o in objects if needs_migration(o['Key'])]
    already_done = [o for o in objects if not needs_migration(o['Key'])]
    print(f'🔄 Objects to migrate: {len(to_migrate)}  (skipping {len(already_done)} already-prefixed)')

    if args.dry_run:
        for o in to_migrate:
            print(f'  COPY  {o["Key"]}  →  {new_key(o["Key"], application_id)}')
        print('(dry-run — no changes made)')
        return

    s3 = boto3.client('s3', region_name=REGION)
    copied, failed = 0, 0
    for o in to_migrate:
        src = o['Key']
        dst = new_key(src, application_id)
        try:
            s3.copy_object(
                Bucket=bucket,
                CopySource={'Bucket': bucket, 'Key': src},
                Key=dst,
            )
            print(f'  ✅  {src}  →  {dst}')
            copied += 1
        except Exception as e:
            print(f'  ❌  {src}  failed: {e}')
            failed += 1

    print(f'\n✅ Copied {copied} objects, {failed} failed.')
    if failed == 0 and copied > 0:
        print('\nOld objects were NOT deleted. Verify the app works, then delete manually:')
        for o in to_migrate:
            print(f'  aws s3 rm s3://{bucket}/{o["Key"]}')


if __name__ == '__main__':
    main()
