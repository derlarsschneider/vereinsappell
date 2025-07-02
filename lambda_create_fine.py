# lambda/createFine.py
import json
import os
import uuid
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

table_name = os.environ.get('FINES_TABLE', 'fines')
sns_topic_arn = os.environ.get('PUSH_TOPIC_ARN')

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

        # Push Notification versenden
        if sns_topic_arn:
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=json.dumps({
                    'type': 'fine',
                    'memberId': member_id,
                    'fineId': fine_id,
                    'reason': reason,
                    'timestamp': timestamp
                }),
                Subject='Neues Strafgeld'
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
