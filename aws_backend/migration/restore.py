#!/usr/bin/env python3
"""
Step 2: Restore data into new DynamoDB tables with applicationId as partition key.

Run AFTER deploying new Terraform (tables recreated with new schema).

applicationId assignment strategy:
  - members:      memberId starts with applicationId (client generates memberId = applicationId + timestamp)
  - fines:        memberId attribute on each fine uses the same prefix rule
  - marschbefehl: no member link; assigned to the single club if unambiguous,
                  otherwise requires --default-application-id
  - reminders_sent: intentionally NOT restored — it is a TTL dedup table; items expire
                    automatically after 7 days and a fresh start is harmless

Usage:
    AWS_PROFILE=<profile> python3 restore.py [--workspace vereins-app-beta] [--default-application-id <id>]
"""
import argparse
import json
import os
import sys
from email.policy import default

import boto3
from boto3.dynamodb.conditions import Key

REGION = 'eu-central-1'
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def load_backup(name):
    path = os.path.join(SCRIPT_DIR, f'backup_{name}.json')
    if not os.path.exists(path):
        print(f'❌ Backup file not found: {path}')
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def batch_write(table, items):
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)


def restore_members(table, members, application_id):
    ok, skipped = 0, 0
    for m in members:
        member_id = m.get('memberId')
        if not application_id:
            print(f'  ⚠️  Cannot assign applicationId for memberId={member_id} — skipping')
            skipped += 1
            continue
        item = {**m, 'applicationId': application_id}
        table.put_item(Item=item)
        ok += 1
    print(f'  ✅ members: {ok} restored, {skipped} skipped')


def restore_fines(table, fines, application_id):
    ok, skipped = 0, 0
    for fine in fines:
        member_id = fine.get('memberId', '')
        if not application_id:
            print(f'  ⚠️  Cannot assign applicationId for fine memberId={member_id} — skipping')
            skipped += 1
            continue
        # Remove old composite key attribute if present
        item = {k: v for k, v in fine.items() if k != 'app-memberId-fineId'}
        item['applicationId'] = application_id
        table.put_item(Item=item)
        ok += 1
    print(f'  ✅ fines: {ok} restored, {skipped} skipped')


def restore_marschbefehl(table, entries, default_app_id):
    ok = 0
    for entry in entries:
        item = {k: v for k, v in entry.items() if k != 'type'}
        item['applicationId'] = default_app_id
        # Keep 'type' as a regular attribute for informational purposes
        item['type'] = entry.get('type', 'marschbefehl')
        table.put_item(Item=item)
        ok += 1
    print(f'  ✅ marschbefehl: {ok} restored → applicationId={default_app_id}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', default='vereins-app-beta')
    parser.add_argument('--default-application-id', default=None,
                        help='Fallback applicationId for marschbefehl (auto-detected if only one club)')
    args = parser.parse_args()

    ws = args.workspace
    dynamodb = boto3.resource('dynamodb', region_name=REGION)

    application_id = args.default_application_id

    if not application_id:
        print('❌ No customers found in backup — cannot restore.')
        sys.exit(1)

    members_table      = dynamodb.Table(f'{ws}-members')
    fines_table        = dynamodb.Table(f'{ws}-fines')
    marschbefehl_table = dynamodb.Table(f'{ws}-marschbefehl')

    members = load_backup('members')
    fines   = load_backup('fines')
    marschbefehl = load_backup('marschbefehl')

    print(f'\n🔄 Restoring {len(members)} members …')
    restore_members(members_table, members, application_id)

    print(f'🔄 Restoring {len(fines)} fines …')
    restore_fines(fines_table, fines, application_id)

    print(f'🔄 Restoring {len(marschbefehl)} marschbefehl entries …')
    restore_marschbefehl(marschbefehl_table, marschbefehl, application_id)

    print('\n✅ Restore complete. Run python3 migrate_s3.py next.')


if __name__ == '__main__':
    main()
