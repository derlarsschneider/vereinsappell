import os

import boto3

# Created once per container (init phase), not per request: building the
# resource costs several hundred ms warm and seconds on a cold 128 MB instance.
_members_table = boto3.resource('dynamodb').Table(os.environ.get('MEMBERS_TABLE_NAME', ''))


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
    response = _members_table.get_item(Key={'applicationId': application_id, 'memberId': member_id})
    return response.get('Item')
