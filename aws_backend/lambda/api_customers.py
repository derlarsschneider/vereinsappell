import json
import os
import boto3

def table():
    dynamodb = boto3.resource('dynamodb')
    customers_table_name = os.environ.get('CUSTOMERS_TABLE_NAME')
    customers_table = dynamodb.Table(customers_table_name)
    return customers_table


def get_customer_by_id(event, context):
    try:
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

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'event': event})
        }
