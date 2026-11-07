import json
import os
import uuid
from datetime import datetime

import boto3
from push_notifications import send_push_notification

dynamodb = boto3.resource('dynamodb')
feedback_table = dynamodb.Table(os.environ.get('FEEDBACK_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL', '')
SUPER_ADMIN_APPLICATION_ID = os.environ.get('SUPER_ADMIN_APPLICATION_ID', '')
SUPER_ADMIN_MEMBER_ID = os.environ.get('SUPER_ADMIN_MEMBER_ID', '')

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def _send_ses_email(subject: str, body: str):
    if not ADMIN_EMAIL:
        return
    ses = boto3.client('ses', region_name='eu-central-1')
    ses.send_email(
        Source=ADMIN_EMAIL,
        Destination={'ToAddresses': [ADMIN_EMAIL]},
        Message={
            'Subject': {'Data': subject},
            'Body': {'Text': {'Data': body}},
        },
    )


def post_feedback(event):
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    body = json.loads(event.get('body', '{}'))

    member = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item', {})
    member_name = member.get('name', member_id)

    feedback_id = str(uuid.uuid4())
    item = {
        'applicationId': application_id,
        'feedbackId': feedback_id,
        'memberId': member_id,
        'memberName': member_name,
        'message': body.get('message', ''),
        'date': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S'),
    }
    if body.get('newsId'):
        item['newsId'] = body['newsId']
    if body.get('newsTitle'):
        item['newsTitle'] = body['newsTitle']
    if body.get('newsQuestion'):
        item['newsQuestion'] = body['newsQuestion']

    feedback_table.put_item(Item=item)

    # Push notification to SuperAdmin
    if SUPER_ADMIN_APPLICATION_ID and SUPER_ADMIN_MEMBER_ID:
        superadmin = members_table.get_item(
            Key={'applicationId': SUPER_ADMIN_APPLICATION_ID, 'memberId': SUPER_ADMIN_MEMBER_ID}
        ).get('Item', {})
        token = superadmin.get('token')
        if token:
            send_push_notification(
                token=token,
                notification={
                    'title': f'Feedback von {member_name}',
                    'body': body.get('message', '')[:100],
                    'url': '/info',
                    'type': 'feedback',
                },
                secret_name='firebase-credentials',
            )

    # Email to admin
    _send_ses_email(
        subject=f'Neues Feedback von {member_name} ({application_id})',
        body=f'Von: {member_name} ({member_id})\nVerein: {application_id}\n\n{body.get("message", "")}',
    )

    return {'statusCode': 200, 'body': json.dumps(item)}


def get_feedback(event):
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')

    member = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item', {})
    is_superadmin = bool(member and member.get('isSuperAdmin'))

    if is_superadmin:
        response = feedback_table.scan()
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = feedback_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))
    else:
        response = feedback_table.query(
            KeyConditionExpression='applicationId = :appId',
            FilterExpression='memberId = :memberId',
            ExpressionAttributeValues={':appId': application_id, ':memberId': member_id},
        )
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = feedback_table.query(
                KeyConditionExpression='applicationId = :appId',
                FilterExpression='memberId = :memberId',
                ExpressionAttributeValues={':appId': application_id, ':memberId': member_id},
                ExclusiveStartKey=response['LastEvaluatedKey'],
            )
            items.extend(response.get('Items', []))

    items.sort(key=lambda i: i.get('date', ''), reverse=True)
    return {'statusCode': 200, 'body': json.dumps(items)}


def post_reply(event):
    if not _is_superadmin(event):
        return _ERROR_403
    application_id = event.get('headers', {}).get('applicationid', '')
    feedback_id = (event.get('pathParameters') or {}).get('feedbackId', '')
    body = json.loads(event.get('body', '{}'))
    reply_text = body.get('reply', '')
    replied_at = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')

    feedback_table.update_item(
        Key={'applicationId': application_id, 'feedbackId': feedback_id},
        UpdateExpression='SET reply = :r, repliedAt = :t',
        ExpressionAttributeValues={':r': reply_text, ':t': replied_at},
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Antwort gespeichert'})}


def handle_feedback(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    if method == 'POST' and path == '/feedback':
        return post_feedback(event)
    elif method == 'GET' and path == '/feedback':
        return get_feedback(event)
    elif method == 'POST' and '/reply' in path:
        return post_reply(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
