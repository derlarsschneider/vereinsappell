import base64
import json
import boto3
import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account


def get_firebase_credentials(secret_name: str) -> dict:
    """
    Lade Firebase Service Account JSON aus AWS Secrets Manager.
    """
    region_name = "eu-central-1"  # anpassen, falls nötig
    client = boto3.client("secretsmanager", region_name=region_name)
    response = client.get_secret_value(SecretId=secret_name)

    if 'SecretString' in response:
        return json.loads(response['SecretString'])
    elif 'SecretBinary' in response:
        return json.loads(base64.b64decode(response["SecretBinary"]))
    else:
        raise ValueError("Secret does not contain a valid SecretString")


def get_access_token(service_account_json: dict) -> str:
    """
    Erzeuge ein Access Token für Firebase HTTP v1 API.
    """
    credentials = service_account.Credentials.from_service_account_info(
        service_account_json,
        scopes=["https://www.googleapis.com/auth/firebase.messaging"],
    )
    credentials.refresh(Request())
    return credentials.token


def send_push_notification(token: str, notification: dict, secret_name: str) -> dict:
    """
    Sende eine Push Notification an ein Gerät mit FCM-Token.
    """
    # Lade Service Account JSON aus Secrets Manager
    service_account_json = get_firebase_credentials(secret_name)
    project_id = service_account_json["project_id"]
    access_token = get_access_token(service_account_json)

    # Erstelle Nachricht
    message = {
        "message": {
            "token": token,
            "notification": notification,
        }
    }

    # Sende POST-Anfrage an Firebase API
    response = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        json=message,
    )

    return {
        "status_code": response.status_code,
        "response": response.json() if response.content else {}
    }
