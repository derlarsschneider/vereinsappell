import json
import os
import uuid

import boto3


def handle_error(event, context):
    try:
        dynamodb = boto3.resource('dynamodb')

        error_table_name = os.environ.get('ERROR_TABLE_NAME')
        error_table = dynamodb.Table(error_table_name)

        error_table.put_item(
            Item={
                'id': str(uuid.uuid4()),
                'error': event
            }
        )

    except Exception as e:
        print(json.dumps({'error': str(e), 'event': event}))
