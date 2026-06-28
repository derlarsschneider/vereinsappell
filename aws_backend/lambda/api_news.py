import json
import os
import uuid
from datetime import datetime

import boto3

dynamodb = boto3.resource('dynamodb')
news_table = dynamodb.Table(os.environ.get('NEWS_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def get_news():
    response = news_table.scan()
    items = response.get('Items', [])
    while 'LastEvaluatedKey' in response:
        response = news_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))

    now = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
    active = [i for i in items if not i.get('expiresAt') or i['expiresAt'] > now]
    active.sort(key=lambda i: i.get('date', ''), reverse=True)
    return {'statusCode': 200, 'body': json.dumps(active)}


def post_news(event):
    if not _is_superadmin(event):
        return _ERROR_403
    body = json.loads(event.get('body', '{}'))
    member_id = event.get('headers', {}).get('memberid', '')
    item = {
        'newsId': str(uuid.uuid4()),
        'title': body.get('title', ''),
        'body': body.get('body', ''),
        'date': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S'),
        'createdBy': member_id,
    }
    if body.get('expiresAt'):
        item['expiresAt'] = body['expiresAt']
    if body.get('question'):
        item['question'] = body['question']
    if body.get('questionOptions'):
        item['questionOptions'] = body['questionOptions']
    news_table.put_item(Item=item)
    return {'statusCode': 200, 'body': json.dumps(item)}


def delete_news(event):
    if not _is_superadmin(event):
        return _ERROR_403
    news_id = (event.get('pathParameters') or {}).get('newsId', '')
    news_table.delete_item(Key={'newsId': news_id})
    return {'statusCode': 200, 'body': json.dumps({'message': 'Gelöscht'})}


def handle_news(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    if method == 'GET' and path == '/news':
        return get_news()
    elif method == 'POST' and path == '/news':
        return post_news(event)
    elif method == 'DELETE' and path.startswith('/news/'):
        return delete_news(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
