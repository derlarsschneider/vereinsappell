import json
import os
import uuid

from botocore.exceptions import ClientError

import boto3

MAX_FIELD_SIZE = 128

def handle_error(event, context, error=''):
    try:
        dynamodb = boto3.resource('dynamodb')

        error_table_name = os.environ.get('ERROR_TABLE_NAME')
        error_table = dynamodb.Table(error_table_name)

        route_key = event.get('routeKey', '')
        headers = event.get('headers', {})
        body_fields = {}
        body = event.get('body', {})

        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                body = {"_raw": body}

        for key, value in body.items():
            val_str = str(value)
            if len(val_str.encode("utf-8")) > MAX_FIELD_SIZE:
                val_str = val_str.encode("utf-8")[:MAX_FIELD_SIZE].decode("utf-8", errors="ignore") + "…"
            body_fields[key] = val_str

        try:
            error_table.put_item(
                Item={
                    'id': str(uuid.uuid4()),
                    'error': error,
                    'route_key': route_key,
                    'headers': headers,
                    'body': body_fields
                }
            )
        except ClientError as e:
            if e.response["Error"]["Code"] == "ValidationException":
                error_table.put_item(
                    Item={
                        'id': str(uuid.uuid4()),
                        'error': 'Dynamodb ValidationException',
                        'dynamodb_error': str(e)
                    }
                )
            else:
                raise

    except Exception as e:
        print('❌❌❌ Error in error_handler')
        print(json.dumps({'error': str(e), 'event': event}))
