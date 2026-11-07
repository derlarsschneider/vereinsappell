#!/usr/bin/env python3
"""
Rotate the memberId of every super-admin row in the members table.

Old super-admin memberIds may have leaked (open Firebase polls/umlagen data,
GET /members before the security hotfix). memberId is the only credential, so
each super-admin row gets a fresh random memberId and the old row is removed.

Per row, one DynamoDB transaction writes the copy with the new memberId,
moves the member's fines to the new memberId and deletes the old row, so a
row is never lost, duplicated or separated from its fines.

Not migrated: Firebase data keyed by memberId (drink tallies, umlagen, poll
votes) and the member's own feedback history.

Alternative for a club where the super admin is also a real member (fines,
drink tallies, votes): --split. It creates a separate super-admin row with a
fresh memberId for administration only, and removes isSuperAdmin from the
personal row. The personal row keeps its memberId and all its data; if that
id leaks, it only grants the personal (club-level) rights. Run --split before
rotating, so the rotation no longer picks up the personal row.

--consolidate --keep X: keep a single super admin. Every super-admin row gets
a fresh memberId; the row in club X stays super admin, all others become plain
club admins (isAdmin). Platform-wide functions only need that one super-admin
account; club work uses the per-club admin accounts. Refuses rows that have
fines (personal accounts) — run --split for those first.

Recommended order:
    1. --split <club where you are a real member> --apply
    2. --consolidate --keep <club for the super-admin account> --apply

Default is a dry run. Nothing is changed without --apply.

Usage:
    python3 rotate_super_admin_ids.py                       # dry run, all clubs
    python3 rotate_super_admin_ids.py --application-id X    # dry run, one club
    python3 rotate_super_admin_ids.py --application-id X --apply
    python3 rotate_super_admin_ids.py --apply               # all clubs
    python3 rotate_super_admin_ids.py --split X             # dry run, role split
    python3 rotate_super_admin_ids.py --split X --apply

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
# Production API endpoint; the app only adds an account from a link that names it.
API_BASE_URL = 'https://v49kyt4758.execute-api.eu-central-1.amazonaws.com'

_serializer = TypeSerializer()


def members_table_name(workspace: str) -> str:
    return f'{workspace}-members'


def fines_table_name(workspace: str) -> str:
    return f'{workspace}-fines'


def build_rotated_item(item: dict, new_member_id: str) -> dict:
    """Copy of the member row with a new memberId; every other attribute is kept."""
    return {**item, 'memberId': new_member_id}


def invite_link(application_id: str, member_id: str) -> str:
    query = urlencode({
        'apiBaseUrl': API_BASE_URL,
        'applicationId': application_id,
        'memberId': member_id,
    })
    return f'{INVITE_BASE_URL}?{query}'


MAX_TRANSACTION_ITEMS = 100


def rotation_transaction(table_name: str, old_item: dict, new_item: dict,
                         fines_table: str = '', fine_ids: list = ()) -> list:
    """TransactItems that put the new row, move the fines and delete the old row atomically."""
    if len(fine_ids) + 2 > MAX_TRANSACTION_ITEMS:
        raise ValueError(f'too many fines ({len(fine_ids)}) for one transaction')
    fine_updates = [
        {
            'Update': {
                'TableName': fines_table,
                'Key': {
                    'applicationId': _serializer.serialize(old_item['applicationId']),
                    'fineId': _serializer.serialize(fine_id),
                },
                'UpdateExpression': 'SET memberId = :new',
                'ConditionExpression': 'memberId = :old',
                'ExpressionAttributeValues': {
                    ':new': _serializer.serialize(new_item['memberId']),
                    ':old': _serializer.serialize(old_item['memberId']),
                },
            }
        }
        for fine_id in fine_ids
    ]
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
        *fine_updates,
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


def fines_by_member(fines_table, rows: list) -> dict:
    """fineIds referencing each old (applicationId, memberId)."""
    keys = {(r['applicationId'], r['memberId']) for r in rows}
    result = {}
    for fine in scan_all(fines_table, ProjectionExpression='applicationId, memberId, fineId'):
        key = (fine.get('applicationId'), fine.get('memberId'))
        if key in keys:
            result.setdefault(key, []).append(fine['fineId'])
    return result


def write_backup(rows: list, directory: str) -> str:
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    path = os.path.join(directory, f'backup_super_admins_{stamp}.json')
    with open(path, 'w') as f:
        json.dump(rows, f, indent=2, default=str)
    return path


def build_consolidated_item(item: dict, new_member_id: str, keep_super_admin: bool) -> dict:
    """Rotated row; outside the kept club it becomes a plain club admin."""
    rotated = build_rotated_item(item, new_member_id)
    if not keep_super_admin:
        rotated['isSuperAdmin'] = False
        rotated['isAdmin'] = True
    return rotated


def run_consolidate(args, dynamodb, client, members_name, members_table) -> int:
    rows = find_super_admins(members_table, None)
    if not rows:
        print('No super-admin rows found.')
        return 0
    if args.keep not in {r['applicationId'] for r in rows}:
        print(f'No super-admin row in the club to keep ({args.keep}).')
        return 1

    names = club_names(dynamodb.Table(CUSTOMERS_TABLE))
    fines_name = fines_table_name(args.workspace)
    fines = fines_by_member(dynamodb.Table(fines_name), rows)
    with_fines = [r for r in rows if fines.get((r['applicationId'], r['memberId']))]
    if with_fines:
        print('These super-admin rows look like personal accounts (they have fines). '
              'Separate them with --split first:')
        for r in with_fines:
            print(f'  {names.get(r["applicationId"], "?")}  {r["applicationId"]}  '
                  f'name={r.get("name", "")!r}')
        return 1

    print(f'{len(rows)} super-admin row(s); every one gets a fresh memberId:')
    for r in rows:
        role = 'stays SUPER ADMIN' if r['applicationId'] == args.keep else 'becomes club admin'
        print(f'  {names.get(r["applicationId"], "?"):<30} name={r.get("name", "")!r:<40} {role}')
    print('⚠️  Not migrated: Firebase data keyed by memberId (drink tallies, umlagen, poll votes) '
          'and own feedback history.')

    if not args.apply:
        print('\nDry run — nothing changed. Re-run with --apply to consolidate.')
        return 0

    answer = input(f'\nConsolidate {len(rows)} row(s)? Type "consolidate" to continue: ')
    if answer.strip() != 'consolidate':
        print('Aborted.')
        return 1

    backup = write_backup(rows, os.path.dirname(os.path.abspath(__file__)))
    print(f'Backup of old rows: {backup}')

    print('\nNew invite links (treat like passwords):')
    failed = 0
    for r in rows:
        keep = r['applicationId'] == args.keep
        new_id = str(uuid.uuid4())
        new_item = build_consolidated_item(r, new_id, keep_super_admin=keep)
        try:
            client.transact_write_items(TransactItems=rotation_transaction(members_name, r, new_item))
        except Exception as e:  # report and continue with the next row
            failed += 1
            print(f'  ❌ {r["applicationId"]} {r["memberId"]}: {e}')
            continue
        label = 'SUPER ADMIN' if keep else 'club admin '
        print(f'  [{label}] {names.get(r["applicationId"], "?"):<30} '
              f'{invite_link(r["applicationId"], new_id)}')

    if failed:
        print(f'\n{failed} row(s) failed and were left unchanged.')
        return 1
    print('\nDone. Old memberIds stop working within 5 minutes.')
    return 0


def default_admin_name(personal_name: str, club_name: str) -> str:
    """'Lars Schiller' + 'Club' -> 'Lars (Club)', matching rows created by POST /customers."""
    first = (personal_name or 'Admin').split()[0]
    return f'{first} ({club_name})'


def build_split_admin_item(application_id: str, new_member_id: str, name: str) -> dict:
    """Dedicated super-admin row, used only for administration."""
    return {
        'applicationId': application_id,
        'memberId': new_member_id,
        'name': name,
        'isSuperAdmin': True,
        'isAdmin': True,
        'isActive': True,
    }


def split_transaction(table_name: str, personal_item: dict, admin_item: dict) -> list:
    """TransactItems that add the admin row and drop isSuperAdmin from the personal row."""
    return [
        {
            'Put': {
                'TableName': table_name,
                'Item': {k: _serializer.serialize(v) for k, v in admin_item.items()},
                'ConditionExpression': 'attribute_not_exists(memberId)',
            }
        },
        {
            'Update': {
                'TableName': table_name,
                'Key': {
                    'applicationId': _serializer.serialize(personal_item['applicationId']),
                    'memberId': _serializer.serialize(personal_item['memberId']),
                },
                'UpdateExpression': 'SET isSuperAdmin = :false',
                'ConditionExpression': 'isSuperAdmin = :true',
                'ExpressionAttributeValues': {
                    ':false': _serializer.serialize(False),
                    ':true': _serializer.serialize(True),
                },
            }
        },
    ]


def run_split(args, dynamodb, client, members_name, members_table) -> int:
    rows = find_super_admins(members_table, args.split)
    if args.member_id:
        rows = [r for r in rows if r['memberId'] == args.member_id]
    if len(rows) != 1:
        print(f'Expected exactly one super-admin row in {args.split}, found {len(rows)}. '
              'Use --member-id to pick one.')
        for r in rows:
            print(f'  memberId={r["memberId"]}  name={r.get("name", "")!r}')
        return 1
    personal = rows[0]
    club = club_names(dynamodb.Table(CUSTOMERS_TABLE)).get(args.split, args.split)
    admin_name = args.name or default_admin_name(personal.get('name', ''), club)

    print(f'Club:          {club} ({args.split})')
    print(f'Personal row:  memberId={personal["memberId"]}  name={personal.get("name", "")!r}')
    print(f'               → keeps everything (fines, Firebase data, isAdmin, token), '
          f'loses isSuperAdmin')
    print(f'New admin row: name={admin_name!r}, isSuperAdmin + isAdmin, fresh random memberId')

    if not args.apply:
        print('\nDry run — nothing changed. Re-run with --apply to split.')
        return 0

    answer = input('\nSplit roles? Type "split" to continue: ')
    if answer.strip() != 'split':
        print('Aborted.')
        return 1

    backup = write_backup([personal], os.path.dirname(os.path.abspath(__file__)))
    print(f'Backup of personal row: {backup}')

    new_id = str(uuid.uuid4())
    admin_item = build_split_admin_item(args.split, new_id, admin_name)
    client.transact_write_items(TransactItems=split_transaction(members_name, personal, admin_item))

    print('\nNew super-admin invite link (treat like a password; use it only for administration):')
    print(f'  {club:<30} {invite_link(args.split, new_id)}')
    print('\nDone. The personal account loses super-admin rights immediately '
          '(the backend re-reads roles on every request).')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--workspace', default='vereins-app-beta')
    parser.add_argument('--application-id', help='only rotate super admins of this club')
    parser.add_argument('--split', metavar='APPLICATION_ID',
                        help='instead of rotating: give this club a separate super-admin row and '
                             'remove isSuperAdmin from the existing (personal) row')
    parser.add_argument('--member-id', help='with --split: the personal row, if the club has several')
    parser.add_argument('--name', help='with --split: name of the new admin row '
                                       '(default: "<first name> (<club>)")')
    parser.add_argument('--consolidate', action='store_true',
                        help='rotate all super-admin rows; only the club given by --keep stays '
                             'super admin, all others become club admins')
    parser.add_argument('--keep', metavar='APPLICATION_ID',
                        help='with --consolidate: the club whose row stays super admin')
    parser.add_argument('--apply', action='store_true', help='actually change data (default: dry run)')
    args = parser.parse_args()
    modes = [m for m in ('split', 'application_id', 'consolidate') if getattr(args, m)]
    if len(modes) > 1:
        parser.error('--split, --application-id and --consolidate cannot be combined')
    if args.consolidate and not args.keep:
        parser.error('--consolidate needs --keep APPLICATION_ID')

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    client = boto3.client('dynamodb', region_name=REGION)
    members_name = members_table_name(args.workspace)
    members_table = dynamodb.Table(members_name)

    if args.split:
        return run_split(args, dynamodb, client, members_name, members_table)
    if args.consolidate:
        return run_consolidate(args, dynamodb, client, members_name, members_table)

    rows = find_super_admins(members_table, args.application_id)
    if not rows:
        print('No super-admin rows found.')
        return 0

    names = club_names(dynamodb.Table(CUSTOMERS_TABLE))
    fines_name = fines_table_name(args.workspace)
    fines = fines_by_member(dynamodb.Table(fines_name), rows)

    print(f'{len(rows)} super-admin row(s) in {members_name}:')
    for r in rows:
        club = names.get(r['applicationId'], '?')
        n_fines = len(fines.get((r['applicationId'], r['memberId']), []))
        print(f'  {club:<30} {r["applicationId"]}  memberId={r["memberId"]}  '
              f'name={r.get("name", "")!r}  fines={n_fines}')

    if any(fines.values()):
        print('\nℹ️  Fines are moved to the new memberId in the same transaction.')
    print('⚠️  Not migrated: Firebase data keyed by memberId (drink tallies, umlagen, poll votes) '
          'and own feedback history.')

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
            fine_ids = fines.get((r['applicationId'], r['memberId']), [])
            client.transact_write_items(
                TransactItems=rotation_transaction(members_name, r, new_item, fines_name, fine_ids)
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
