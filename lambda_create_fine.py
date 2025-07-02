# lambda/createFine.py
import json
import os
import uuid
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('FINES_TABLE', 'fines')
table = dynamodb.Table(table_name)

def handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        member_id = body.get('memberId')
        reason = body.get('reason', 'Keine Angabe')

        if not member_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'memberId ist erforderlich'})
            }

        fine_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()

        table.put_item(
            Item={
                'fineId': fine_id,
                'memberId': member_id,
                'reason': reason,
                'createdAt': timestamp
            }
        )

        return {
            'statusCode': 200,
            'body': json.dumps({'fineId': fine_id})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
