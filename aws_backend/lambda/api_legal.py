import json
import os

import boto3

dynamodb = boto3.resource('dynamodb')
legal_texts_table = dynamodb.Table(os.environ.get('LEGAL_TEXTS_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def get_legal():
    datenschutz = legal_texts_table.get_item(Key={'id': 'datenschutz'}).get('Item', {})
    impressum = legal_texts_table.get_item(Key={'id': 'impressum'}).get('Item', {})
    return {
        'statusCode': 200,
        'body': json.dumps({
            'datenschutz': datenschutz.get('text', ''),
            'impressum': impressum.get('text', ''),
        }),
    }


def put_legal(event):
    if not _is_superadmin(event):
        return _ERROR_403
    body = json.loads(event.get('body', '{}'))
    legal_texts_table.put_item(Item={'id': 'datenschutz', 'text': body.get('datenschutz', '')})
    legal_texts_table.put_item(Item={'id': 'impressum', 'text': body.get('impressum', '')})
    return {'statusCode': 200, 'body': json.dumps({'message': 'Gespeichert'})}


def handle_legal(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    if method == 'GET':
        return get_legal()
    elif method == 'PUT':
        return put_legal(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
