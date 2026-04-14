import os
import re
from datetime import datetime, timezone, timedelta

import boto3
from dateutil import parser as dateutil_parser
from dateutil.tz import gettz

from push_notifications import send_push_notification


# ── ICS parsing ──────────────────────────────────────────────────────────────

def parse_events(ics_content: str) -> list:
    """Parse VEVENT blocks from an ICS string.

    Returns a list of dicts with keys: uid (str), summary (str), dtstart (datetime UTC-aware).
    Events missing uid, summary, or dtstart are skipped.
    """
    events = []
    current = {}
    in_event = False

    # Unfold RFC 5545 continuation lines (CRLF or LF + whitespace)
    unfolded = re.sub(r'\r?\n[ \t]', '', ics_content)

    for raw_line in unfolded.split('\n'):
        line = raw_line.rstrip('\r')

        if line == 'BEGIN:VEVENT':
            in_event = True
            current = {}
        elif line == 'END:VEVENT':
            in_event = False
            if 'uid' in current and 'dtstart' in current and 'summary' in current:
                events.append(current)
        elif in_event:
            if line.startswith('UID:'):
                current['uid'] = line[4:].strip()
            elif line.upper().startswith('DTSTART'):
                header, _, value = line.partition(':')
                tzid_match = re.search(r'TZID=([^;:]+)', header)
                tzid = tzid_match.group(1) if tzid_match else None
                try:
                    dt = dateutil_parser.parse(value.strip())
                    if tzid and dt.tzinfo is None:
                        tz = gettz(tzid)
                        if tz:
                            dt = dt.replace(tzinfo=tz)
                    elif dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    current['dtstart'] = dt.astimezone(timezone.utc)
                except Exception:
                    pass
            elif line.startswith('SUMMARY:'):
                current['summary'] = line[8:].strip()

    return events


# ── Module-level resources (replaced in tests) ────────────────────────────────

_dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

members_table = _dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))
reminders_table = _dynamodb.Table(os.environ.get('REMINDERS_TABLE_NAME', ''))

_FIREBASE_SECRET = os.environ.get('FIREBASE_SECRET_NAME', 'firebase-credentials')


# ── S3 helper ─────────────────────────────────────────────────────────────────

def _get_ics_content() -> str:
    date = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    key = f'calendar/calendar_{date}.ics'
    bucket = os.environ.get('S3_BUCKET_NAME', '')
    obj = s3_client.get_object(Bucket=bucket, Key=key)
    return obj['Body'].read().decode('utf-8')


# ── Lambda handler ────────────────────────────────────────────────────────────

def check_reminders(event, context):
    try:
        ics_content = _get_ics_content()
    except Exception as e:
        print(f'Failed to load ICS from S3: {e}')
        return {'statusCode': 500, 'body': f'ICS load failed: {e}'}

    events = parse_events(ics_content)
    if not events:
        print('No events in ICS')
        return {'statusCode': 200, 'body': 'no events'}

    now = datetime.now(timezone.utc)
    members_resp = members_table.scan()
    members = members_resp.get('Items', [])

    for member in members:
        token = member.get('token', '')
        if not token:
            continue
        if not member.get('reminderEnabled', True):
            continue

        hours_before = int(member.get('reminderHoursBefore', 24))
        member_id = member['memberId']

        for ev in events:
            hours_until = (ev['dtstart'] - now).total_seconds() / 3600
            if not (hours_before - 1 <= hours_until < hours_before):
                continue

            uid = ev['uid']

            try:
                hit = reminders_table.get_item(Key={'memberId': member_id, 'eventId': uid})
                if 'Item' in hit:
                    print(f'Already sent: {member_id}/{uid}')
                    continue
            except Exception as e:
                print(f'Dedup check error: {e}')
                continue

            dt_str = ev['dtstart'].strftime('%d.%m.%Y %H:%M Uhr')
            try:
                send_push_notification(
                    token=token,
                    notification={
                        'title': f'Erinnerung: {ev["summary"]}',
                        'body': f'Termin am {dt_str}',
                        'type': 'reminder',
                    },
                    secret_name=_FIREBASE_SECRET,
                )
                print(f'Notification sent: {member_id}/{uid}')

                ttl = int((ev['dtstart'] + timedelta(days=7)).timestamp())
                reminders_table.put_item(Item={
                    'memberId': member_id,
                    'eventId': uid,
                    'ttl': ttl,
                })
            except Exception as e:
                print(f'Failed to notify {member_id}/{uid}: {e}')

    return {'statusCode': 200, 'body': 'done'}
