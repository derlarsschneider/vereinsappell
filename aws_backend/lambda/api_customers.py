import json
import os
import boto3

def table():
    dynamodb = boto3.resource('dynamodb')
    customers_table_name = os.environ.get('CUSTOMERS_TABLE_NAME')
    customers_table = dynamodb.Table(customers_table_name)
    return customers_table


ALL_SCREEN_KEYS = ['termine', 'marschbefehl', 'strafen', 'dokumente', 'galerie', 'schere_stein_papier']
API_BASE_URL = os.environ.get('API_BASE_URL', '')


def list_customers():
    t = table()
    items = []
    response = t.scan()
    items.extend(response.get('Items', []))
    while 'LastEvaluatedKey' in response:
        response = t.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }


def update_customer(event):
    customer_id = event['pathParameters']['customerId']
    body = json.loads(event['body'])

    update_expr = 'SET application_name = :name, active_screens = :screens'
    expr_values = {
        ':name': body.get('application_name', ''),
        ':screens': body.get('active_screens', ALL_SCREEN_KEYS),
    }
    logo = body.get('application_logo', '')
    if logo:
        update_expr += ', application_logo = :logo'
        expr_values[':logo'] = logo

    table().update_item(
        Key={'application_id': customer_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Verein aktualisiert'})
    }


def create_customer(event):
    body = json.loads(event['body'])
    application_id = body['application_id']
    application_name = body['application_name']
    api_url = body.get('api_url') or API_BASE_URL
    application_logo = body.get('application_logo', '')
    active_screens = body.get('active_screens', ALL_SCREEN_KEYS)

    t = table()
    response = t.get_item(Key={'application_id': application_id})
    if response.get('Item'):
        return {
            'statusCode': 409,
            'body': json.dumps({'error': 'Verein existiert bereits'})
        }

    item = {
        'application_id': application_id,
        'application_name': application_name,
        'api_url': api_url,
        'application_logo': application_logo,
        'active_screens': active_screens,
    }
    t.put_item(Item=item)

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }


def get_customer_by_id(event, context):
    customer_id = event['pathParameters']['customerId']

    response = table().get_item(
        Key={'application_id': customer_id}
    )

    item = response.get('Item')

    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Verein nicht gefunden'})
        }

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }
