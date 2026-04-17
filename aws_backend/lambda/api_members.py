import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

members_table_name = os.environ.get('MEMBERS_TABLE_NAME')
members_table = dynamodb.Table(members_table_name)

ERROR_403 = {
    'statusCode': 403,
    'body': json.dumps({'error': 'Nicht berechtigt'})
}


def handle_members(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    member_id = event.get('pathParameters', {}).get('memberId', '')
    request_headers = event.get('headers', {})
    application_id = request_headers.get('applicationid', '')
    executing_member_id = request_headers.get('memberid', '')
    executing_member = _get_member_by_id(application_id, executing_member_id) or {}
    is_admin = executing_member.get('isAdmin', False)
    is_spiess = executing_member.get('isSpiess', False)
    is_myself = executing_member.get('memberId') == member_id

    if method == 'GET' and path == '/members':
        if not is_admin and not is_spiess:
            return ERROR_403
        return add_headers(list_members(application_id), event=event)
    elif method == 'GET':
        if path.endswith('/all'):
            if not is_admin:
                return ERROR_403
            return add_headers(get_member(application_id, member_id, True), event=event)
        else:
            if not is_admin and not is_spiess and not is_myself:
                return ERROR_403
            return add_headers(get_member(application_id, member_id, False), event=event)
    elif method == 'POST':
        if not is_admin:
            return ERROR_403
        return add_headers(add_member(event['body'], application_id), event=event)
    elif method == 'DELETE':
        if not is_admin:
            return ERROR_403
        return add_headers(delete_member(application_id, member_id), event=event)


def add_headers(response, more_fields={}, event=None):
    origin = (event or {}).get('headers', {}).get('origin', 'https://vereinsappell.web.app')
    response_headers = {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Headers': 'Content-Type,applicationId,memberId,password',
        'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE',
    }
    return {**response_headers, **response, **more_fields}


def _get_member_by_id(application_id, member_id):
    if not application_id or not member_id:
        return None
    response = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    )
    return response.get('Item')


def get_member(application_id, member_id, all_details):
    item = _get_member_by_id(application_id, member_id)
    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Mitglied nicht gefunden'})
        }
    result = item if all_details else {
        'memberId': item['memberId'],
        'name': item['name'],
        'isAdmin': item.get('isAdmin', False),
        'isSpiess': item.get('isSpiess', False),
        'isSuperAdmin': item.get('isSuperAdmin', False),
        'isActive': item.get('isActive', True),
        'token': item.get('token', ''),
    }
    return {'statusCode': 200, 'body': json.dumps(result)}


def list_members(application_id):
    from boto3.dynamodb.conditions import Key
    items = []
    response = members_table.query(
        KeyConditionExpression=Key('applicationId').eq(application_id)
    )
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = members_table.query(
            KeyConditionExpression=Key('applicationId').eq(application_id),
            ExclusiveStartKey=response['LastEvaluatedKey'],
        )
        items.extend(response['Items'])
    return {'statusCode': 200, 'body': json.dumps(items)}


def add_member(body, application_id):
    data = json.loads(body)
    data_member_id = data['memberId']

    members_table.update_item(
        Key={'applicationId': application_id, 'memberId': data_member_id},
        UpdateExpression=(
            'SET #name = :name, isAdmin = :isAdmin, isSpiess = :isSpiess, '
            'isActive = :isActive, #token = :token, street = :street, '
            'houseNumber = :houseNumber, postalCode = :postalCode, '
            'city = :city, phone1 = :phone1, phone2 = :phone2'
        ),
        ExpressionAttributeNames={'#name': 'name', '#token': 'token'},
        ExpressionAttributeValues={
            ':name': data['name'],
            ':isAdmin': data.get('isAdmin', False),
            ':isSpiess': data.get('isSpiess', False),
            ':isActive': data.get('isActive', True),
            ':token': data.get('token', ''),
            ':street': data.get('street', ''),
            ':houseNumber': data.get('houseNumber', ''),
            ':postalCode': data.get('postalCode', ''),
            ':city': data.get('city', ''),
            ':phone1': data.get('phone1', ''),
            ':phone2': data.get('phone2', ''),
        },
    )

    return {
        'statusCode': 200,
        'body': json.dumps({
            'memberId': data_member_id,
            'name': data['name'],
            'isAdmin': data.get('isAdmin', False),
            'isSpiess': data.get('isSpiess', False),
            'isActive': data.get('isActive', True),
            'token': data.get('token', ''),
            'street': data.get('street', ''),
            'houseNumber': data.get('houseNumber', ''),
            'postalCode': data.get('postalCode', ''),
            'city': data.get('city', ''),
            'phone1': data.get('phone1', ''),
            'phone2': data.get('phone2', ''),
        })
    }


def delete_member(application_id, member_id):
    members_table.delete_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Mitglied gelöscht'})}
