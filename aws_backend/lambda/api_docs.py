import base64
import json
import os
import urllib.parse
import boto3

s3 = boto3.client('s3')
s3_bucket_name = os.environ.get('S3_BUCKET_NAME')

# 🔒 Passwortschutz (einfach, aber effektiv)
DOCS_PASSWORD = os.environ.get('DOCS_PASSWORD', 'geheim123')

import re

_VALID_DOC_NAME = re.compile(r'^[A-Za-z0-9._\-/]+$')

def _is_valid_doc_name(name: str) -> bool:
    """Reject names with path traversal or disallowed characters."""
    if not name or not _VALID_DOC_NAME.match(name):
        return False
    # Block path traversal even after normalization
    if '..' in name.split('/'):
        return False
    return True


def handle_docs(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    member_id = event.get('pathParameters', {}).get('memberId', {})
    request_headers = event.get("headers", {})
    executing_member_id = request_headers.get("memberid", "")
    # executing_member = _get_member_by_id(executing_member_id) or {}
    # is_admin = executing_member.get('isAdmin', False)
    # is_spiess = executing_member.get('isSpiess', False)
    # is_myself =  executing_member.get('memberId') == member_id
    if method == 'GET' and path == '/docs':
        return _add_headers(get_docs(event), event=event)
    elif method == 'GET' and path.startswith('/docs/'):
        return _add_headers(get_doc(event), event=event)
    elif method == 'POST' and path.startswith('/docs'):
        return _add_headers(add_doc(event), event=event)
    elif method == 'DELETE' and path.startswith('/docs/'):
        return _add_headers(delete_doc(event), event=event)

def _add_headers(response, more_fields={}, event=None):
    origin = (event or {}).get('headers', {}).get('origin', 'https://vereinsappell.web.app')
    response_headers = {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Headers": "Content-Type,applicationId,memberId,password",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
    }
    return {**response_headers, **response, **more_fields}

def _unauthorized():
    return {
        "statusCode": 401,
        "body": json.dumps({"error": "Unauthorized"}),
        "headers": {
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
            "Access-Control-Allow-Headers": "Content-Type,applicationId,memberId,password",
            "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
        },
    }


def _check_password(event):
    headers = event.get("headers") or {}
    client_pw = headers.get("password")
    return client_pw == DOCS_PASSWORD


def get_docs(event, prefix: str = "docs"):
    if not _check_password(event):
        return _unauthorized()

    response = s3.list_objects_v2(Bucket=s3_bucket_name, Prefix=f"{prefix}/")
    contents = response.get("Contents", [])
    files = [{"name": obj["Key"].removeprefix(f"{prefix}/")} for obj in contents]

    return {
        "statusCode": 200,
        "body": json.dumps(files),
        "headers": {
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
            "Content-Type": "application/json",
        },
    }


def get_doc(event, prefix: str = "docs"):
    if not _check_password(event):
        return _unauthorized()

    file_name = event["pathParameters"]["fileName"]
    file_name = urllib.parse.unquote(file_name)
    key = f"{prefix}/{file_name}"

    try:
        response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    except s3.exceptions.ClientError as e:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": "Datei nicht gefunden"}),
        }

    file_bytes = response["Body"].read()
    content_type = response.get("ContentType", "application/octet-stream")

    return {
        "statusCode": 200,
        "isBase64Encoded": True,
        "headers": {
            "Content-Type": content_type,
            "Content-Disposition": f'inline; filename="{file_name}"',
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
        },
        "body": base64.b64encode(file_bytes).decode("utf-8"),
    }


def add_doc(event, prefix: str = "docs"):
    if not _check_password(event):
        return _unauthorized()

    body = base64.b64decode(event["body"]) if event.get("isBase64Encoded") else event["body"].encode("utf-8")
    data = json.loads(body)
    name = data["name"]
    if not _is_valid_doc_name(name):
        return {"statusCode": 400, "body": json.dumps({"error": "Ungültiger Dateiname"})}
    file_base64 = data["file"]
    key = f"{prefix}/{name}"

    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return {"statusCode": 409, "body": json.dumps({"error": "Datei existiert bereits"})}
    except s3.exceptions.ClientError as e:
        if e.response["Error"]["Code"] != "404":
            raise

    file_bytes = base64.b64decode(file_base64)
    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=file_bytes)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"{name} erfolgreich hochgeladen"}),
        "headers": {
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
        },
    }


def delete_doc(event, prefix: str = "docs"):
    if not _check_password(event):
        return _unauthorized()

    file_name = event["pathParameters"]["fileName"]
    file_name = urllib.parse.unquote(file_name)
    key = f"{prefix}/{file_name}"

    s3.delete_object(Bucket=s3_bucket_name, Key=key)
    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"{file_name} gelöscht"}),
        "headers": {
            "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
        },
    }
