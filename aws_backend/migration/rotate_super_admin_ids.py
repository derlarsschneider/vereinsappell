#!/usr/bin/env python3
"""
Rotate the memberId of every super-admin row in the members table.

Old super-admin memberIds may have leaked (open Firebase polls/umlagen data,
GET /members before the security hotfix). memberId is the only credential, so
each super-admin row gets a fresh random memberId and the old row is removed.

Per row, one DynamoDB transaction writes the copy with the new memberId and
deletes the old row, so a row is never lost or duplicated.

Default is a dry run. Nothing is changed without --apply.

Usage:
    python3 rotate_super_admin_ids.py                       # dry run, all clubs
    python3 rotate_super_admin_ids.py --application-id X    # dry run, one club
    python3 rotate_super_admin_ids.py --application-id X --apply
    python3 rotate_super_admin_ids.py --apply               # all clubs

After --apply:
  - the printed invite links are the new logins (treat them like passwords),
  - old memberIds stop working within 5 minutes (authorizer cache TTL),
  - re-open the app on your devices via the new links.
"""
import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone
from urllib.parse import urlencode

import boto3
from boto3.dynamodb.types import TypeSerializer

REGION = 'eu-central-1'
CUSTOMERS_TABLE = 'vereinsappell-customers'
INVITE_BASE_URL = 'https://vereinsappell.web.app'

_serializer = TypeSerializer()


def members_table_name(workspace: str) -> str:
    return f'{workspace}-members'


def fines_table_name(workspace: str) -> str:
    return f'{workspace}-fines'


def build_rotated_item(item: dict, new_member_id: str) -> dict:
    """Copy of the member row with a new memberId; every other attribute is kept."""
    return {**item, 'memberId': new_member_id}


def invite_link(application_id: str, member_id: str) -> str:
    return f'{INVITE_BASE_URL}?{urlencode({"applicationId": application_id, "memberId": member_id})}'


def rotation_transaction(table_name: str, old_item: dict, new_item: dict) -> list:
    """TransactItems that put the new row and delete the old one atomically."""
    return [
        {
            'Put': {
                'TableName': table_name,
                'Item': {k: _serializer.serialize(v) for k, v in new_item.items()},
                'ConditionExpression': 'attribute_not_exists(memberId)',
            }
        },
        {
            'Delete': {
                'TableName': table_name,
                'Key': {
                    'applicationId': _serializer.serialize(old_item['applicationId']),
                    'memberId': _serializer.serialize(old_item['memberId']),
                },
                'ConditionExpression': 'attribute_exists(memberId)',
            }
        },
    ]


def scan_all(table, **kwargs) -> list:
    items = []
    response = table.scan(**kwargs)
    items.extend(response.get('Items', []))
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'], **kwargs)
        items.extend(response.get('Items', []))
    return items


def find_super_admins(members_table, application_id: str | None) -> list:
    from boto3.dynamodb.conditions import Attr
    rows = scan_all(members_table, FilterExpression=Attr('isSuperAdmin').eq(True))
    if application_id:
        rows = [r for r in rows if r['applicationId'] == application_id]
    return sorted(rows, key=lambda r: (r['applicationId'], r['memberId']))


def club_names(customers_table) -> dict:
    return {c['application_id']: c.get('application_name', c['application_id'])
            for c in scan_all(customers_table)}


def count_fines(fines_table, rows: list) -> dict:
    """Number of fines referencing each old (applicationId, memberId)."""
    keys = {(r['applicationId'], r['memberId']) for r in rows}
    counts = {}
    for fine in scan_all(fines_table, ProjectionExpression='applicationId, memberId'):
        key = (fine.get('applicationId'), fine.get('memberId'))
        if key in keys:
            counts[key] = counts.get(key, 0) + 1
    return counts


def write_backup(rows: list, directory: str) -> str:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    path = os.path.join(directory, f'backup_super_admins_{stamp}.json')
    with open(path, 'w') as f:
        json.dump(rows, f, indent=2, default=str)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--workspace', default='vereins-app-beta')
    parser.add_argument('--application-id', help='only rotate super admins of this club')
    parser.add_argument('--apply', action='store_true', help='actually rotate (default: dry run)')
    args = parser.parse_args()

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    client = boto3.client('dynamodb', region_name=REGION)
    members_name = members_table_name(args.workspace)
    members_table = dynamodb.Table(members_name)

    rows = find_super_admins(members_table, args.application_id)
    if not rows:
        print('No super-admin rows found.')
        return 0

    names = club_names(dynamodb.Table(CUSTOMERS_TABLE))
    fines = count_fines(dynamodb.Table(fines_table_name(args.workspace)), rows)

    print(f'{len(rows)} super-admin row(s) in {members_name}:')
    for r in rows:
        club = names.get(r['applicationId'], '?')
        n_fines = fines.get((r['applicationId'], r['memberId']), 0)
        print(f'  {club:<30} {r["applicationId"]}  memberId={r["memberId"]}  '
              f'name={r.get("name", "")!r}  fines={n_fines}')

    if any(fines.values()):
        print('\n⚠️  Some rows have fines. Fines keep the old memberId and will no longer show '
              'for the rotated account. Rotate anyway only if that is acceptable.')

    if not args.apply:
        print('\nDry run — nothing changed. Re-run with --apply to rotate.')
        return 0

    answer = input(f'\nRotate {len(rows)} row(s)? Type "rotate" to continue: ')
    if answer.strip() != 'rotate':
        print('Aborted.')
        return 1

    backup = write_backup(rows, os.path.dirname(os.path.abspath(__file__)))
    print(f'Backup of old rows: {backup}')

    print('\nNew invite links (treat like passwords):')
    failed = 0
    for r in rows:
        new_id = str(uuid.uuid4())
        new_item = build_rotated_item(r, new_id)
        try:
            client.transact_write_items(
                TransactItems=rotation_transaction(members_name, r, new_item)
            )
        except Exception as e:  # report and continue with the next row
            failed += 1
            print(f'  ❌ {r["applicationId"]} {r["memberId"]}: {e}')
            continue
        club = names.get(r['applicationId'], '?')
        print(f'  {club:<30} {invite_link(r["applicationId"], new_id)}')

    if failed:
        print(f'\n{failed} row(s) failed and were left unchanged.')
        return 1
    print('\nDone. Old memberIds stop working within 5 minutes.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
