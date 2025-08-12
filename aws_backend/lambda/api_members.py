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
    member_id = event.get('pathParameters', {}).get('memberId', {})
    request_headers = event.get("headers", {})
    executing_member_id = request_headers.get("memberid", "")
    executing_member = _get_member_by_id(executing_member_id) or {}
    is_admin = executing_member.get('isAdmin', False)
    is_spiess = executing_member.get('isSpiess', False)
    is_myself =  executing_member.get('memberId') == member_id

    if method == 'GET' and path == '/members':
        # LIST members
        if not is_admin and not is_spiess:
            return ERROR_403
        return add_headers(list_members())
    elif method == 'GET':
        if path.endswith('/all'):
            # GET member with all details
            if not is_admin:
                return ERROR_403
            return add_headers(get_member(member_id, True), {'memberId': member_id})
        else:
            # GET member with reduced details
            if not is_admin and not is_spiess and not is_myself:
                return ERROR_403
            return add_headers(get_member(member_id, False))
    elif method == 'POST':
        # ADD member
        if not is_admin:
            return ERROR_403
        return add_headers(add_member(event['body']))
    elif method == 'DELETE':
        # DELETE member
        if not is_admin:
            return ERROR_403
        return add_headers(delete_member(member_id))


def add_headers(response, more_fields={}):
    response_headers = {
        "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
    }
    return {**response_headers, **response, **more_fields}

def _get_member_by_id(member_id):
    response = members_table.get_item(
        Key={'memberId': member_id}
    )
    item = response.get('Item')
    return item


def get_member(member_id, all_details):
    item = _get_member_by_id(member_id)
    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Mitglied nicht gefunden'})
        }
    if all_details:
        result = item
    else:
        result = {
            'memberId': item['memberId'],
            'name': item['name'],
            'isAdmin': item.get('isAdmin', False),
            'isSpiess': item.get('isSpiess', False),
            'token': item.get('token', ''),
        }

    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }


def list_members():
    items = []

    response = members_table.scan()
    items.extend(response['Items'])

    # Falls es mehr als 1MB Daten sind, wird die Scan-Operation paginiert
    while 'LastEvaluatedKey' in response:
        response = members_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }


def add_member(body):
    data = json.loads(body)
    data_member_id = data['memberId']
    data_name = data['name']
    data_is_admin = data.get('isAdmin', False)
    data_is_spiess = data.get('isSpiess', False)
    data_token = data.get('token', '')
    data_street = data.get('street', '')
    data_house_number = data.get('houseNumber', '')
    data_postal_code = data.get('postalCode', '')
    data_city = data.get('city', '')
    data_phone1 = data.get('phone1', '')
    data_phone2 = data.get('phone2', '')


    item = {
        'memberId': data_member_id,
        'name': data_name,
        'isAdmin': data_is_admin,
        'isSpiess': data_is_spiess,
        'token': data_token,
        'street': data_street,
        'houseNumber': data_house_number,
        'postalCode': data_postal_code,
        'city': data_city,
        'phone1': data_phone1,
        'phone2': data_phone2,
    }

    members_table.put_item(Item=item)

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }


def delete_member(member_id):
    members_table.delete_item(
        Key={'memberId': member_id}
    )

    return {'statusCode': 200, 'body': json.dumps({'message': 'Mitglied gelöscht'})}
