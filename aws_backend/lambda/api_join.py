import json
import os
import boto3

ses = boto3.client('ses', region_name='eu-central-1')

_CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'OPTIONS,POST',
}

_REQUIRED_CLUB = {'clubName', 'contact', 'email'}
_REQUIRED_MEMBER = {'name', 'clubName', 'email'}


def _contact_email():
    return os.environ.get('CONTACT_EMAIL', 'info@vereinsappell.de')


def _bad_request(msg):
    return {'statusCode': 400, 'headers': _CORS, 'body': json.dumps({'error': msg})}


def _ok():
    return {'statusCode': 200, 'headers': _CORS, 'body': json.dumps({'ok': True})}


def handle_join_club(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 204, 'headers': _CORS}

    try:
        data = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return _bad_request('Invalid JSON')

    missing = _REQUIRED_CLUB - set(k for k, v in data.items() if v)
    if missing:
        return _bad_request(f'Missing fields: {", ".join(sorted(missing))}')

    lines = [
        f'Vereinsname: {data["clubName"]}',
        f'Ansprechpartner: {data["contact"]}',
        f'E-Mail: {data["email"]}',
    ]
    if data.get('phone'):
        lines.append(f'Telefon: {data["phone"]}')
    if data.get('message'):
        lines.append(f'\nNachricht:\n{data["message"]}')

    body = '\n'.join(lines)
    ses.send_email(
        Source=_contact_email(),
        Destination={'ToAddresses': [_contact_email()]},
        Message={
            'Subject': {'Data': f'Neue Vereinsanmeldung: {data["clubName"]}'},
            'Body': {'Text': {'Data': body}},
        },
        ReplyToAddresses=[data['email']],
    )
    return _ok()


def handle_join_member(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 204, 'headers': _CORS}

    try:
        data = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        return _bad_request('Invalid JSON')

    missing = _REQUIRED_MEMBER - set(k for k, v in data.items() if v)
    if missing:
        return _bad_request(f'Missing fields: {", ".join(sorted(missing))}')

    lines = [
        f'Name: {data["name"]}',
        f'Vereinsname: {data["clubName"]}',
        f'E-Mail: {data["email"]}',
    ]
    if data.get('message'):
        lines.append(f'\nNachricht:\n{data["message"]}')

    body = '\n'.join(lines)
    ses.send_email(
        Source=_contact_email(),
        Destination={'ToAddresses': [_contact_email()]},
        Message={
            'Subject': {'Data': f'Beitrittsanfrage: {data["name"]} → {data["clubName"]}'},
            'Body': {'Text': {'Data': body}},
        },
        ReplyToAddresses=[data['email']],
    )
    return _ok()
