import base64
import json
import urllib.request

import boto3
from google.auth.transport.requests import Request
from google.oauth2 import service_account

_DATABASE_SCOPE = 'https://www.googleapis.com/auth/firebase.database'


def _get_token(secret_name: str) -> str:
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=secret_name)
    if 'SecretString' in response:
        sa_json = json.loads(response['SecretString'])
    else:
        sa_json = json.loads(base64.b64decode(response['SecretBinary']))
    credentials = service_account.Credentials.from_service_account_info(
        sa_json, scopes=[_DATABASE_SCOPE]
    )
    credentials.refresh(Request())
    return credentials.token


def backup_polls(database_url: str, secret_name: str, s3_client, bucket: str, timestamp: str) -> None:
    token = _get_token(secret_name)
    url = f'{database_url.rstrip("/")}/polls.json'
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req) as resp:
        data = resp.read()
    s3_client.put_object(
        Bucket=bucket,
        Key=f'firebase/{timestamp}/polls.json',
        Body=data,
        ContentType='application/json',
    )


def restore_polls(database_url: str, secret_name: str, s3_client, bucket: str, timestamp: str) -> None:
    obj = s3_client.get_object(Bucket=bucket, Key=f'firebase/{timestamp}/polls.json')
    data = obj['Body'].read()
    token = _get_token(secret_name)
    url = f'{database_url.rstrip("/")}/polls.json'
    req = urllib.request.Request(
        url,
        data=data,
        method='PUT',
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
        },
    )
    urllib.request.urlopen(req)
