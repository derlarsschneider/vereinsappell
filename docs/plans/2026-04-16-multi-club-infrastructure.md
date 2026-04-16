# Multi-Club Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable multiple independent clubs on a single backend by isolating all data via `applicationId`. A new club requires only a DynamoDB entry — no new infrastructure.

**Architecture:** Single Lambda, single API Gateway, single set of DynamoDB tables. Every table uses `applicationId` as partition key. All Lambda handlers extract `applicationId` from the request header and use it in every read/write. S3 keys are prefixed with `applicationId/`. The existing `vereinsappell-customers` table acts as the registry of valid application IDs (authorizer already validates against it).

**Tech Stack:** Terraform (default workspace, no workspace feature), AWS Lambda Python 3.10, DynamoDB, API Gateway v2, S3, Route53/ACM

---

## Context for subagents

- All Terraform commands run from `aws_backend/`
- Full deploy command: `bash aws_backend/update_backend.sh`
- Lambda headers arrive **lowercased** — `applicationId` header is read as `event['headers']['applicationid']`
- The authorizer (`aws_backend/authorizer/authorizer.py`) already validates that `applicationId` exists in the `vereinsappell-customers` table — no changes needed there
- All commits in English, no `Co-Authored-By` line
- Plans live in `docs/plans/`, specs in `docs/specs/`

---

## New DynamoDB schemas

| Table | Old schema | New schema |
|---|---|---|
| `vereinsappell-members` | PK `memberId` | PK `applicationId`, SK `memberId` |
| `vereinsappell-fines` | PK `memberId`, SK `fineId` | PK `memberKey` (`appId#memberId`), SK `fineId` |
| `vereinsappell-marschbefehl` | PK `type`, SK `datetime` | PK `applicationId`, SK `datetime` |
| `vereinsappell-customers` | PK `application_id` — **unchanged** | — |
| `vereinsappell-error` | PK `id` — **unchanged** | — |

**Why `memberKey` for fines?** The main query is "all fines for one member" → composite key `appId#memberId` lets DynamoDB answer that in a single Query without a scan or GSI.

---

## Files changed

| File | Action |
|---|---|
| `aws_backend/main.tf` | Remove `terraform.workspace`, use fixed `name_prefix = "vereinsappell"` |
| `aws_backend/api_members.tf` | Update table schema (new key attributes) |
| `aws_backend/api_fines.tf` | Update table schema (new key attributes) |
| `aws_backend/api_marschbefehl.tf` | Update table schema (new key attributes) |
| `aws_backend/update_backend.sh` | Remove workspace selection |
| `aws_backend/authorizer/update.sh` | Remove hardcoded function name |
| `aws_backend/lambda/update.sh` | Remove hardcoded function name |
| `aws_backend/lambda/api_members.py` | Use `applicationId` in all DynamoDB calls |
| `aws_backend/lambda/lambda_handler.py` | Use `applicationId` in fines, marschbefehl, photos |
| `aws_backend/lambda/api_docs.py` | Prefix all S3 keys with `applicationId/` |
| `scripts/migrate_to_multi_club.py` | **Create** — one-time data migration script |

---

## Task 1: Remove Terraform workspace usage

Replace `terraform.workspace` with a fixed prefix. Remove workspace selection from all deploy scripts. This makes the infrastructure independent of which workspace is active.

**Files:**
- Modify: `aws_backend/main.tf`
- Modify: `aws_backend/update_backend.sh`
- Modify: `aws_backend/authorizer/update.sh`
- Modify: `aws_backend/lambda/update.sh`

- [ ] **Step 1: Update main.tf locals**

Replace the `locals` block in `aws_backend/main.tf`:
```hcl
locals {
    name_prefix = "vereinsappell"
}
```

Full file after change:
```hcl
provider "aws" {
    region = "eu-central-1"
}

variable "aws_region" {
    default = "eu-central-1"
}

terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

locals {
    name_prefix = "vereinsappell"
}

data "aws_caller_identity" "current" {}
```

- [ ] **Step 2: Update update_backend.sh — remove workspace selection**

Replace `aws_backend/update_backend.sh` with:
```bash
#!/bin/bash -e

set -euo pipefail

SKIP_BUILD="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD="1"
      shift
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

authorizer/zip.sh
lambda/zip.sh

terraform init -input=false
terraform apply -auto-approve

authorizer/update.sh

if [ "${SKIP_BUILD}" == "1" ]; then
  echo "⚠️ --skip-build flag set, skipping lambda build."
  lambda/update.sh
else
  lambda/build.sh && lambda/update.sh
fi

echo "✅ Backend wurde aktualisiert."
```

- [ ] **Step 3: Update authorizer/update.sh — use fixed function name**

Replace `aws_backend/authorizer/update.sh` with:
```bash
#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereinsappell-lambda_authorizer"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
./zip.sh
aws lambda update-function-code \
  --function-name "$FUNC_NAME" \
  --zip-file fileb://"$ZIP"
```

- [ ] **Step 4: Update lambda/update.sh — use fixed function name**

Replace `aws_backend/lambda/update.sh` with:
```bash
#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereinsappell-lambda_backend"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
./zip.sh
aws lambda update-function-code \
  --function-name "$FUNC_NAME" \
  --zip-file fileb://"$ZIP"
```

- [ ] **Step 5: Commit**

```bash
git add aws_backend/main.tf aws_backend/update_backend.sh aws_backend/authorizer/update.sh aws_backend/lambda/update.sh
git commit -m "refactor: remove Terraform workspace usage, use fixed name prefix"
```

---

## Task 2: Update DynamoDB table schemas in Terraform

DynamoDB primary keys cannot be changed in-place. Terraform will destroy and recreate each table. **All existing data will be lost from these tables** — the migration script in Task 8 restores it.

**Files:**
- Modify: `aws_backend/api_members.tf`
- Modify: `aws_backend/api_fines.tf`
- Modify: `aws_backend/api_marschbefehl.tf`

- [ ] **Step 1: Update members table schema**

In `aws_backend/api_members.tf`, replace the `aws_dynamodb_table` resource:
```hcl
resource "aws_dynamodb_table" "members_table" {
    name         = "${local.name_prefix}-members"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "applicationId"
    range_key    = "memberId"

    attribute {
        name = "applicationId"
        type = "S"
    }
    attribute {
        name = "memberId"
        type = "S"
    }
}
```

Keep all `aws_apigatewayv2_route` resources in that file unchanged.

- [ ] **Step 2: Update fines table schema**

In `aws_backend/api_fines.tf`, replace the `aws_dynamodb_table` resource:
```hcl
resource "aws_dynamodb_table" "fines_table" {
    name         = "${local.name_prefix}-fines"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "memberKey"
    range_key    = "fineId"

    attribute {
        name = "memberKey"
        type = "S"
    }
    attribute {
        name = "fineId"
        type = "S"
    }
}
```

`memberKey` stores the composite value `{applicationId}#{memberId}` (e.g. `"abc-123#member-001"`).

Keep all `aws_apigatewayv2_route` resources unchanged.

- [ ] **Step 3: Update marschbefehl table schema**

In `aws_backend/api_marschbefehl.tf`, replace the `aws_dynamodb_table` resource:
```hcl
resource "aws_dynamodb_table" "marschbefehl_table" {
    name         = "${local.name_prefix}-marschbefehl"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "applicationId"
    range_key    = "datetime"

    attribute {
        name = "applicationId"
        type = "S"
    }
    attribute {
        name = "datetime"
        type = "S"
    }
}
```

Keep all `aws_apigatewayv2_route` resources unchanged.

- [ ] **Step 4: Commit**

```bash
git add aws_backend/api_members.tf aws_backend/api_fines.tf aws_backend/api_marschbefehl.tf
git commit -m "feat: add applicationId partition key to members, fines, marschbefehl tables"
```

---

## Task 3: Update api_members.py for applicationId-scoped operations

Every DynamoDB call must use `applicationId` as part of the key. The helper `_get_member_by_id` becomes `_get_member` and takes `app_id` as first argument.

**Files:**
- Modify: `aws_backend/lambda/api_members.py`

- [ ] **Step 1: Rewrite api_members.py**

Replace the entire file content:
```python
import json
import os
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

members_table_name = os.environ.get('MEMBERS_TABLE_NAME')
members_table = dynamodb.Table(members_table_name)

ERROR_403 = {
    'statusCode': 403,
    'body': json.dumps({'error': 'Nicht berechtigt'})
}


def handle_members(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    member_id = event.get('pathParameters', {}).get('memberId', '')
    request_headers = event.get("headers", {})
    app_id = request_headers.get("applicationid", "")
    executing_member_id = request_headers.get("memberid", "")
    executing_member = _get_member(app_id, executing_member_id) or {}
    is_admin = executing_member.get('isAdmin', False)
    is_spiess = executing_member.get('isSpiess', False)
    is_myself = executing_member.get('memberId') == member_id

    if method == 'GET' and path == '/members':
        if not is_admin and not is_spiess:
            return ERROR_403
        return add_headers(list_members(app_id), event=event)
    elif method == 'GET':
        if path.endswith('/all'):
            if not is_admin:
                return ERROR_403
            return add_headers(get_member(app_id, member_id, True), event=event)
        else:
            if not is_admin and not is_spiess and not is_myself:
                return ERROR_403
            return add_headers(get_member(app_id, member_id, False), event=event)
    elif method == 'POST':
        if not is_admin:
            return ERROR_403
        return add_headers(add_member(app_id, event['body']), event=event)
    elif method == 'DELETE':
        if not is_admin:
            return ERROR_403
        return add_headers(delete_member(app_id, member_id), event=event)


def add_headers(response, more_fields={}, event=None):
    origin = (event or {}).get('headers', {}).get('origin', 'https://vereinsappell.web.app')
    response_headers = {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Headers": "Content-Type,applicationId,memberId,password",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,DELETE",
    }
    return {**response_headers, **response, **more_fields}


def _get_member(app_id, member_id):
    response = members_table.get_item(
        Key={'applicationId': app_id, 'memberId': member_id}
    )
    return response.get('Item')


def get_member(app_id, member_id, all_details):
    item = _get_member(app_id, member_id)
    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Mitglied nicht gefunden'})
        }
    if all_details:
        result = item
    else:
        result = {
            'memberId': item['memberId'],
            'name': item['name'],
            'isAdmin': item.get('isAdmin', False),
            'isSpiess': item.get('isSpiess', False),
            'token': item.get('token', ''),
        }
    return {'statusCode': 200, 'body': json.dumps(result)}


def list_members(app_id):
    items = []
    response = members_table.query(
        KeyConditionExpression=Key('applicationId').eq(app_id)
    )
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = members_table.query(
            KeyConditionExpression=Key('applicationId').eq(app_id),
            ExclusiveStartKey=response['LastEvaluatedKey']
        )
        items.extend(response['Items'])
    return {'statusCode': 200, 'body': json.dumps(items)}


def add_member(app_id, body):
    data = json.loads(body)
    item = {
        'applicationId': app_id,
        'memberId': data['memberId'],
        'name': data['name'],
        'isAdmin': data.get('isAdmin', False),
        'isSpiess': data.get('isSpiess', False),
        'isActive': data.get('isActive', True),
        'token': data.get('token', ''),
        'street': data.get('street', ''),
        'houseNumber': data.get('houseNumber', ''),
        'postalCode': data.get('postalCode', ''),
        'city': data.get('city', ''),
        'phone1': data.get('phone1', ''),
        'phone2': data.get('phone2', ''),
    }
    members_table.put_item(Item=item)
    return {'statusCode': 200, 'body': json.dumps(item)}


def delete_member(app_id, member_id):
    members_table.delete_item(
        Key={'applicationId': app_id, 'memberId': member_id}
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Mitglied gelöscht'})}
```

- [ ] **Step 2: Commit**

```bash
git add aws_backend/lambda/api_members.py
git commit -m "feat: scope members table operations by applicationId"
```

---

## Task 4: Update fines and marschbefehl in lambda_handler.py

`get_fines`, `add_fine`, `delete_fine`, and `get_marschbefehl` all need `applicationId` from the request headers.

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`

- [ ] **Step 1: Replace get_fines**

In `aws_backend/lambda/lambda_handler.py`, replace the `get_fines` function:
```python
def get_fines(event):
    params = event.get('queryStringParameters') or {}
    member_id = params.get('memberId')
    app_id = event.get('headers', {}).get('applicationid', '')

    if not member_id:
        return {'statusCode': 400, 'body': json.dumps({'error': 'memberId fehlt'})}

    member = members_table.get_item(
        Key={'applicationId': app_id, 'memberId': member_id}
    ).get('Item', {})
    name = member.get('name', member_id)

    member_key = f"{app_id}#{member_id}"
    fines_response = fines_table.query(
        KeyConditionExpression=Key('memberKey').eq(member_key)
    )
    items = fines_response.get('Items', [])
    return {
        'statusCode': 200,
        'body': json.dumps({"name": name, "fines": items}, cls=DecimalEncoder)
    }
```

- [ ] **Step 2: Replace add_fine**

Replace the `add_fine` function:
```python
def add_fine(event):
    data = json.loads(event['body'])
    member_id = data['memberId']
    app_id = event.get('headers', {}).get('applicationid', '')
    reason = data['reason']
    amount = data['amount']
    fine_id = str(uuid.uuid4())
    member_key = f"{app_id}#{member_id}"

    item = {
        'memberKey': member_key,
        'fineId': fine_id,
        'memberId': member_id,
        'applicationId': app_id,
        'reason': reason,
        'amount': amount,
    }
    fines_table.put_item(Item=item)

    member = members_table.get_item(
        Key={'applicationId': app_id, 'memberId': member_id}
    ).get('Item', {})
    name = member.get('name')
    token = member.get('token')

    if token:
        push_response = send_push_notification(
            token=token,
            notification={
                'title': f'Neue Strafe für {name}',
                'body': f'{reason} ({amount} €)',
                'url': '/strafen',
                'type': 'fine',
            },
            secret_name='firebase-credentials'
        )
        item['pushResponse'] = push_response

    return {'statusCode': 200, 'body': json.dumps(item)}
```

- [ ] **Step 3: Replace delete_fine**

Replace the `delete_fine` function:
```python
def delete_fine(event):
    fine_id = event['pathParameters']['fineId']
    member_id = event['queryStringParameters']['memberId']
    app_id = event.get('headers', {}).get('applicationid', '')
    member_key = f"{app_id}#{member_id}"

    fines_table.delete_item(
        Key={'memberKey': member_key, 'fineId': fine_id}
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Strafe gelöscht'})}
```

- [ ] **Step 4: Replace get_marschbefehl**

Replace the `get_marschbefehl` function:
```python
def get_marschbefehl(event):
    app_id = event.get('headers', {}).get('applicationid', '')
    now = datetime.now()
    datetimestamp = now.strftime("%Y-%m-%d")

    items = []
    query_filter = Key('applicationId').eq(app_id) & Key('datetime').gte(datetimestamp)
    response = marschbefehl_table.query(
        KeyConditionExpression=query_filter,
    )
    items.extend(response['Items'])

    while 'LastEvaluatedKey' in response:
        response = marschbefehl_table.query(
            KeyConditionExpression=query_filter,
            ExclusiveStartKey=response['LastEvaluatedKey'],
        )
        items.extend(response['Items'])

    return {'statusCode': 200, 'body': json.dumps(items)}
```

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: scope fines and marschbefehl operations by applicationId"
```

---

## Task 5: Update api_docs.py for applicationId-prefixed S3 paths

S3 keys change from `docs/file.pdf` to `{applicationId}/docs/file.pdf`. This prevents one club from seeing another club's documents.

**Files:**
- Modify: `aws_backend/lambda/api_docs.py`

- [ ] **Step 1: Rewrite api_docs.py**

Replace the entire file content:
```python
import base64
import json
import os
import re
import urllib.parse
import boto3

s3 = boto3.client('s3')
s3_bucket_name = os.environ.get('S3_BUCKET_NAME')

DOCS_PASSWORD = os.environ.get('DOCS_PASSWORD', 'geheim123')

_VALID_DOC_NAME = re.compile(r'^[A-Za-z0-9._\-/]+$')


def _is_valid_doc_name(name: str) -> bool:
    if not name or not _VALID_DOC_NAME.match(name):
        return False
    if '..' in name.split('/'):
        return False
    return True


def _get_app_id(event: dict) -> str:
    return event.get('headers', {}).get('applicationid', '')


def _s3_prefix(app_id: str, folder: str = 'docs') -> str:
    """Returns the S3 prefix for a club's folder, e.g. 'abc123/docs'."""
    return f"{app_id}/{folder}"


def handle_docs(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    app_id = _get_app_id(event)

    if method == 'GET' and path == '/docs':
        return _add_headers(get_docs(event, app_id), event=event)
    elif method == 'GET' and path.startswith('/docs/'):
        return _add_headers(get_doc(event, app_id), event=event)
    elif method == 'POST' and path.startswith('/docs'):
        return _add_headers(add_doc(event, app_id), event=event)
    elif method == 'DELETE' and path.startswith('/docs/'):
        return _add_headers(delete_doc(event, app_id), event=event)


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


def get_docs(event, app_id: str):
    if not _check_password(event):
        return _unauthorized()

    prefix = _s3_prefix(app_id)
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


def get_doc(event, app_id: str):
    if not _check_password(event):
        return _unauthorized()

    file_name = event["pathParameters"]["fileName"]
    file_name = urllib.parse.unquote(file_name)
    key = f"{_s3_prefix(app_id)}/{file_name}"

    try:
        response = s3.get_object(Bucket=s3_bucket_name, Key=key)
    except s3.exceptions.ClientError:
        return {"statusCode": 404, "body": json.dumps({"error": "Datei nicht gefunden"})}

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


def add_doc(event, app_id: str):
    if not _check_password(event):
        return _unauthorized()

    body = base64.b64decode(event["body"]) if event.get("isBase64Encoded") else event["body"].encode("utf-8")
    data = json.loads(body)
    name = data["name"]

    if not _is_valid_doc_name(name):
        return {"statusCode": 400, "body": json.dumps({"error": "Ungültiger Dateiname"})}

    key = f"{_s3_prefix(app_id)}/{name}"

    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return {"statusCode": 409, "body": json.dumps({"error": "Datei existiert bereits"})}
    except s3.exceptions.ClientError as e:
        if e.response["Error"]["Code"] != "404":
            raise

    file_bytes = base64.b64decode(data["file"])
    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=file_bytes)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"{name} erfolgreich hochgeladen"}),
        "headers": {"Access-Control-Allow-Origin": "https://vereinsappell.web.app"},
    }


def delete_doc(event, app_id: str):
    if not _check_password(event):
        return _unauthorized()

    file_name = event["pathParameters"]["fileName"]
    file_name = urllib.parse.unquote(file_name)
    key = f"{_s3_prefix(app_id)}/{file_name}"

    s3.delete_object(Bucket=s3_bucket_name, Key=key)
    return {
        "statusCode": 200,
        "body": json.dumps({"message": f"{file_name} gelöscht"}),
        "headers": {"Access-Control-Allow-Origin": "https://vereinsappell.web.app"},
    }
```

- [ ] **Step 2: Commit**

```bash
git add aws_backend/lambda/api_docs.py
git commit -m "feat: prefix S3 doc keys with applicationId for club isolation"
```

---

## Task 6: Update photos handlers in lambda_handler.py

The `/photos` routes call `get_docs` and `add_docs` in `lambda_handler.py` (not `api_docs.py`). These also need `applicationId`-prefixed S3 keys.

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`

- [ ] **Step 1: Replace get_docs (used for /photos)**

In `aws_backend/lambda/lambda_handler.py`, replace the `get_docs` function:
```python
def get_docs(event, prefix: str = 'docs'):
    app_id = event.get('headers', {}).get('applicationid', '')
    s3_prefix = f"{app_id}/{prefix}" if app_id else prefix
    proxy = event.get('pathParameters', {}).get('proxy')
    if proxy is not None:
        s3_prefix = f"{s3_prefix}/{proxy}"
    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=s3_prefix)
        response = s3.get_object(Bucket=s3_bucket_name, Key=s3_prefix)
        file_bytes = response['Body'].read()
        content_type = response.get('ContentType', 'application/octet-stream')
        return {
            'statusCode': 200,
            'isBase64Encoded': True,
            'headers': {
                'Content-Type': content_type,
                'Content-Disposition': f'inline; filename="{proxy}"',
                'Access-Control-Allow-Origin': '*',
            },
            'body': base64.b64encode(file_bytes).decode('utf-8'),
        }
    except s3.exceptions.ClientError:
        files = list_s3_files(s3_prefix)
        return {"statusCode": 200, "body": json.dumps(files)}
```

- [ ] **Step 2: Replace add_docs (used for /photos)**

Replace the `add_docs` function:
```python
def add_docs(event, prefix: str = 'docs'):
    app_id = event.get('headers', {}).get('applicationid', '')
    s3_prefix = f"{app_id}/{prefix}" if app_id else prefix
    body = base64.b64decode(event['body']) if event.get('isBase64Encoded') else event['body'].encode('utf-8')
    data = json.loads(body)
    name = data['name']
    key = f"{s3_prefix}/{name}"
    s3 = boto3.client('s3')
    try:
        s3.head_object(Bucket=s3_bucket_name, Key=key)
        return message_response(409, "Datei existiert bereits")
    except s3.exceptions.ClientError as e:
        if e.response['Error']['Code'] != '404':
            raise
    file_bytes = base64.b64decode(data['file'])
    s3.put_object(Bucket=s3_bucket_name, Key=key, Body=file_bytes)
    return message_response(200, str(name))
```

- [ ] **Step 3: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: prefix photos S3 keys with applicationId for club isolation"
```

---

## Task 7: Deploy new infrastructure

Terraform will destroy and recreate the three tables with new schemas. The existing `vereinsappell-customers` table is not touched (its schema is unchanged).

- [ ] **Step 1: Run terraform plan to review changes**

```bash
cd aws_backend
terraform init -input=false
terraform plan
```

Confirm the plan shows:
- `aws_dynamodb_table.members_table` — destroyed and recreated (key change)
- `aws_dynamodb_table.fines_table` — destroyed and recreated (key change)
- `aws_dynamodb_table.marschbefehl_table` — destroyed and recreated (key change)
- Lambda functions — updated in-place (name change: `vereins-app-beta-*` → `vereinsappell-*`)
- No destruction of `aws_dynamodb_table.customer_config_table`

If the plan shows `aws_dynamodb_table.customer_config_table` being created and an error about duplicate table, import it first:
```bash
terraform import aws_dynamodb_table.customer_config_table vereinsappell-customers
```
Then re-run `terraform plan`.

- [ ] **Step 2: Deploy**

```bash
bash update_backend.sh
```

Expected last line: `✅ Backend wurde aktualisiert.`

- [ ] **Step 3: Verify new tables exist**

```bash
aws dynamodb list-tables --region eu-central-1 | grep vereinsappell
```

Expected output includes:
```
"vereinsappell-members"
"vereinsappell-fines"
"vereinsappell-marschbefehl"
"vereinsappell-customers"
```

---

## Task 8: Migrate existing data

Reads from the old `vereins-app-beta-*` tables and writes to the new `vereinsappell-*` tables with the correct `applicationId` key structure. Run **once** after Task 7.

**Files:**
- Create: `scripts/migrate_to_multi_club.py`

- [ ] **Step 1: Get the applicationId of the existing club**

```bash
aws dynamodb scan \
  --table-name vereinsappell-customers \
  --region eu-central-1 \
  --query 'Items[*].{id:application_id.S,name:application_name.S}'
```

Note down the `application_id` value — used as `--app-id` in Step 3.

- [ ] **Step 2: Create the migration script**

Create `scripts/migrate_to_multi_club.py`:
```python
"""
One-time migration: reads from old vereins-app-beta-* tables,
writes to new vereinsappell-* tables with applicationId keys.

Usage:
    python3 scripts/migrate_to_multi_club.py --app-id <APPLICATION_ID>
"""
import argparse
import boto3

REGION = 'eu-central-1'
OLD_PREFIX = 'vereins-app-beta'
NEW_PREFIX = 'vereinsappell'


def scan_all(table):
    items = []
    response = table.scan()
    items.extend(response['Items'])
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    return items


def migrate_members(dynamodb, app_id):
    old = dynamodb.Table(f'{OLD_PREFIX}-members')
    new = dynamodb.Table(f'{NEW_PREFIX}-members')
    items = scan_all(old)
    for item in items:
        new_item = {**item, 'applicationId': app_id}
        new.put_item(Item=new_item)
    print(f'members: migrated {len(items)} items')


def migrate_fines(dynamodb, app_id):
    old = dynamodb.Table(f'{OLD_PREFIX}-fines')
    new = dynamodb.Table(f'{NEW_PREFIX}-fines')
    items = scan_all(old)
    for item in items:
        member_id = item['memberId']
        new_item = {
            **item,
            'memberKey': f'{app_id}#{member_id}',
            'applicationId': app_id,
        }
        new_item.pop('app-memberId-fineId', None)  # remove legacy attribute
        new.put_item(Item=new_item)
    print(f'fines: migrated {len(items)} items')


def migrate_marschbefehl(dynamodb, app_id):
    old = dynamodb.Table(f'{OLD_PREFIX}-marschbefehl')
    new = dynamodb.Table(f'{NEW_PREFIX}-marschbefehl')
    items = scan_all(old)
    for item in items:
        new_item = {**item, 'applicationId': app_id}
        # 'type' kept as a regular attribute — no longer a key
        new.put_item(Item=new_item)
    print(f'marschbefehl: migrated {len(items)} items')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-id', required=True, help='applicationId of the existing club')
    args = parser.parse_args()

    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    print(f'Migrating data for applicationId: {args.app_id}')
    migrate_members(dynamodb, args.app_id)
    migrate_fines(dynamodb, args.app_id)
    migrate_marschbefehl(dynamodb, args.app_id)
    print('Migration complete.')
```

- [ ] **Step 3: Run the migration**

Replace `<APPLICATION_ID>` with the value from Step 1:
```bash
python3 scripts/migrate_to_multi_club.py --app-id <APPLICATION_ID>
```

Expected output:
```
Migrating data for applicationId: <APPLICATION_ID>
members: migrated N items
fines: migrated N items
marschbefehl: migrated N items
Migration complete.
```

- [ ] **Step 4: Verify member count matches**

```bash
aws dynamodb scan --table-name vereinsappell-members --region eu-central-1 --select COUNT --query 'Count'
aws dynamodb scan --table-name vereins-app-beta-members --region eu-central-1 --select COUNT --query 'Count'
```

Both numbers must be equal.

- [ ] **Step 5: Commit migration script**

```bash
git add scripts/migrate_to_multi_club.py
git commit -m "feat: add one-time migration script for multi-club schema"
```

---

## Task 9: End-to-end test + provision second club

Verify the existing club works with the new schema, then add a second club without any infrastructure changes.

- [ ] **Step 1: Smoke test — existing club list members**

Replace `<APP_ID>` and `<MEMBER_ID>` with real values from the existing club:
```bash
curl -s \
  -H "applicationId: <APP_ID>" \
  -H "memberId: <MEMBER_ID>" \
  "https://vereinsappell.derlarsschneider.de/members" | python3 -m json.tool | head -30
```

Expected: HTTP 200 with JSON array of member objects, each containing `applicationId`.

- [ ] **Step 2: Smoke test — authorizer rejects unknown applicationId**

```bash
curl -o /dev/null -w "%{http_code}\n" \
  -H "applicationId: does-not-exist" \
  -H "memberId: x" \
  "https://vereinsappell.derlarsschneider.de/members"
```

Expected: `403`

- [ ] **Step 3: Provision second club — generate applicationId**

```bash
python3 -c "import uuid; print(uuid.uuid4())"
```

Save this value as `NEW_APP_ID`.

- [ ] **Step 4: Register second club in customers table**

Replace `<NEW_APP_ID>` and `<CLUB_NAME>`:
```bash
aws dynamodb put-item \
  --table-name vereinsappell-customers \
  --region eu-central-1 \
  --item '{
    "application_id": {"S": "<NEW_APP_ID>"},
    "application_name": {"S": "<CLUB_NAME>"},
    "application_logo": {"S": ""},
    "api_url": {"S": "https://vereinsappell.derlarsschneider.de"}
  }'
```

- [ ] **Step 5: Create first admin member for second club**

Replace `<NEW_APP_ID>`, `<MEMBER_ID>` (e.g. `admin-001`), `<NAME>`:
```bash
aws dynamodb put-item \
  --table-name vereinsappell-members \
  --region eu-central-1 \
  --item '{
    "applicationId": {"S": "<NEW_APP_ID>"},
    "memberId": {"S": "<MEMBER_ID>"},
    "name": {"S": "<NAME>"},
    "isAdmin": {"BOOL": true},
    "isSpiess": {"BOOL": false},
    "isActive": {"BOOL": true},
    "token": {"S": ""},
    "street": {"S": ""},
    "houseNumber": {"S": ""},
    "postalCode": {"S": ""},
    "city": {"S": ""},
    "phone1": {"S": ""},
    "phone2": {"S": ""}
  }'
```

- [ ] **Step 6: Verify second club only sees its own members**

```bash
curl -s \
  -H "applicationId: <NEW_APP_ID>" \
  -H "memberId: <MEMBER_ID>" \
  "https://vereinsappell.derlarsschneider.de/members" | python3 -m json.tool
```

Expected: HTTP 200 with array containing **only** the one admin member — no members from the first club visible.

- [ ] **Step 7: Generate provisioning QR payload**

The Flutter app is configured by scanning a QR code with this JSON:
```json
{
  "apiBaseUrl": "https://vereinsappell.derlarsschneider.de",
  "applicationId": "<NEW_APP_ID>",
  "memberId": "<MEMBER_ID>"
}
```

Generate with `qrencode` (install: `sudo apt install qrencode`):
```bash
qrencode -o /tmp/qr-second-club.png \
  "{\"apiBaseUrl\":\"https://vereinsappell.derlarsschneider.de\",\"applicationId\":\"<NEW_APP_ID>\",\"memberId\":\"<MEMBER_ID>\"}"
```

Or configure directly in browser:
```
https://vereinsappell.web.app/?apiBaseUrl=https://vereinsappell.derlarsschneider.de&applicationId=<NEW_APP_ID>&memberId=<MEMBER_ID>
```

---

## Done

After Task 9 the system supports any number of clubs:
- Single backend, single API endpoint, single set of DynamoDB tables
- Data fully isolated by `applicationId` at every read/write
- S3 documents isolated by `{applicationId}/docs/` and `{applicationId}/photos/` prefixes
- Adding a new club = one DynamoDB entry + member records, zero infrastructure changes
