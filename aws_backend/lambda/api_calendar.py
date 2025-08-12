import json
import os
import requests
import boto3
from datetime import datetime

def get_calendar(event, context):
    try:
        s3 = boto3.client('s3')
        s3_bucket_name = os.environ.get('S3_BUCKET_NAME')
        date = datetime.now().strftime('%Y-%m-%d')
        s3_key = f'calendar/calendar_{date}.ics'

        try:
            s3.head_object(Bucket=s3_bucket_name, Key=s3_key)
            ics_content = s3.get_object(Bucket=s3_bucket_name, Key=s3_key)
            print(ics_content)
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "bucket": s3_bucket_name,
                    "key": s3_key,
                    "ics_content": ics_content.decode('utf-8'),
                })
            }

        except:

            print('Download ICS-Datei')
            response = requests.get('https://www.schuetzenlust-gnadental.de/index.php/termine/eventslist/?format=raw&layout=ics')
            response.raise_for_status()

            ics_content = response.content

            print('Upload ICS to S3')
            s3.put_object(
                Bucket=s3_bucket_name,
                Key=s3_key,
                Body=ics_content,
                ContentType='text/calendar'
            )
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "bucket": s3_bucket_name,
                    "key": s3_key,
                    "ics_content": ics_content.decode('utf-8'),
                })
            }

    except requests.RequestException as e:
        print(f'❌ Exception in get_calendar')
        print(json.dumps({'error': str(e)}))
        print(json.dumps({'event': event}))
        return {
            "statusCode": 500,
            "body": {
                "error": f"Fehler beim Herunterladen der ICS-Datei: {str(e)}"
            }
        }
