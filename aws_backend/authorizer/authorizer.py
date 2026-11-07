import os

import boto3


def lambda_authorizer(event, context):
    if event.get('source') == 'aws.events':
        return {'isAuthorized': True}
    headers = event.get('headers') or {}
    application_id = headers.get('applicationid', '')
    member_id = headers.get('memberid', '')
    if not application_id or not member_id:
        return {'isAuthorized': False}

    member = _get_member(application_id, member_id)
    if member is None:
        return {'isAuthorized': False}

    # Legacy rows without isActive count as active; super admins may always pass
    is_active = member.get('isActive', True)
    if is_active or member.get('isSuperAdmin'):
        return {'isAuthorized': True}
    return {'isAuthorized': False}


def _get_member(application_id, member_id):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(os.environ['MEMBERS_TABLE_NAME'])
    response = table.get_item(Key={'applicationId': application_id, 'memberId': member_id})
    return response.get('Item')
