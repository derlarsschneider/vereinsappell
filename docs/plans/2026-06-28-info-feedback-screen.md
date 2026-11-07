# Info & Feedback Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Info & Feedback" screen with three tabs: app-wide news (SuperAdmin publishes), member feedback with admin replies, and legal texts (Datenschutzerklärung + Impressum).

**Architecture:** Three new DynamoDB tables (`news_table`, `feedback_table`, `legal_texts_table`) backed by three new Python Lambda modules wired into the existing dispatcher. Four new Flutter files (3 API clients + 1 screen with `DefaultTabController`). The screen is always visible to all active members regardless of `active_screens`.

**Tech Stack:** Python 3.x (Lambda), boto3 (DynamoDB), AWS SES (email), Firebase push notifications (existing `push_notifications.py`), Flutter/Dart, `http` package, `provider` package, `intl` package (date formatting).

**Spec:** `docs/specs/2026-06-28-info-feedback-screen-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `aws_backend/lambda/api_legal.py` | GET/PUT /legal |
| Create | `aws_backend/lambda/api_news.py` | GET/POST/DELETE /news |
| Create | `aws_backend/lambda/api_feedback.py` | GET/POST /feedback, POST /feedback/{id}/reply, SES + push |
| Modify | `aws_backend/lambda/lambda_handler.py` | Wire new routes |
| Create | `aws_backend/lambda/tests/test_api_legal.py` | Backend tests for legal |
| Create | `aws_backend/lambda/tests/test_api_news.py` | Backend tests for news |
| Create | `aws_backend/lambda/tests/test_api_feedback.py` | Backend tests for feedback |
| Create | `lib/api/legal_api.dart` | Flutter GET/PUT /legal |
| Create | `lib/api/news_api.dart` | Flutter GET/POST/DELETE /news |
| Create | `lib/api/feedback_api.dart` | Flutter GET/POST /feedback, POST reply |
| Create | `lib/screens/info_feedback_screen.dart` | 3-tab screen |
| Modify | `lib/screens/home_screen.dart` | Add menu tile |
| Modify | `.gitignore` | Ignore `.superpowers/` |

---

## Task 1: DynamoDB Tables + Lambda Env Vars

No code tests for infrastructure. Create the three tables in AWS and add env vars.

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py` (add table references at top)

- [ ] **Step 1: Create DynamoDB tables in AWS console (or CLI)**

```bash
# Run these three commands in your AWS account:

aws dynamodb create-table \
  --table-name vereinsappell-news \
  --attribute-definitions AttributeName=newsId,AttributeType=S \
  --key-schema AttributeName=newsId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

aws dynamodb create-table \
  --table-name vereinsappell-feedback \
  --attribute-definitions \
    AttributeName=applicationId,AttributeType=S \
    AttributeName=feedbackId,AttributeType=S \
  --key-schema \
    AttributeName=applicationId,KeyType=HASH \
    AttributeName=feedbackId,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

aws dynamodb create-table \
  --table-name vereinsappell-legal-texts \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

- [ ] **Step 2: Add env vars to Lambda function**

In the AWS Lambda console (or your deployment config), add:

```
NEWS_TABLE_NAME=vereinsappell-news
FEEDBACK_TABLE_NAME=vereinsappell-feedback
LEGAL_TEXTS_TABLE_NAME=vereinsappell-legal-texts
ADMIN_EMAIL=derlarsschiller@gmail.com
SUPER_ADMIN_APPLICATION_ID=<your-applicationId-where-superadmin-member-lives>
SUPER_ADMIN_MEMBER_ID=<your-memberId-that-has-isSuperAdmin=true>
```

- [ ] **Step 3: Add IAM permission for SES**

In the Lambda execution role, add inline policy:

```json
{
  "Effect": "Allow",
  "Action": "ses:SendEmail",
  "Resource": "*"
}
```

Also verify your sender address in SES (AWS Console → SES → Verified identities → Create identity → Email address → enter `derlarsschiller@gmail.com`). SES will send a verification email.

- [ ] **Step 4: Add table handles in lambda_handler.py**

In `aws_backend/lambda/lambda_handler.py`, after the existing table declarations (around line 26), add:

```python
news_table_name = os.environ.get('NEWS_TABLE_NAME')
feedback_table_name = os.environ.get('FEEDBACK_TABLE_NAME')
legal_texts_table_name = os.environ.get('LEGAL_TEXTS_TABLE_NAME')
```

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: add env var declarations for news, feedback and legal tables"
```

---

## Task 2: Backend — api_legal.py

**Files:**
- Create: `aws_backend/lambda/api_legal.py`
- Create: `aws_backend/lambda/tests/test_api_legal.py`

- [ ] **Step 1: Write failing tests**

Create `aws_backend/lambda/tests/test_api_legal.py`:

```python
import json
import sys
import unittest
from unittest.mock import MagicMock

sys.modules.setdefault('boto3', MagicMock())
sys.path.insert(0, '.')
import api_legal

APP_ID = 'app-123'
SUPER_ADMIN_ID = 'superadmin1'


def _event(method, path, member_id='user1', body=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': APP_ID, 'memberid': member_id},
    }
    if body:
        event['body'] = json.dumps(body)
    return event


class TestGetLegal(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_legal.legal_texts_table = self.mock_table

    def test_get_legal_returns_datenschutz_and_impressum(self):
        self.mock_table.get_item.side_effect = [
            {'Item': {'id': 'datenschutz', 'text': 'Datenschutz Text'}},
            {'Item': {'id': 'impressum', 'text': 'Impressum Text'}},
        ]
        response = api_legal.get_legal()
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['datenschutz'], 'Datenschutz Text')
        self.assertEqual(body['impressum'], 'Impressum Text')

    def test_get_legal_returns_empty_strings_when_not_set(self):
        self.mock_table.get_item.return_value = {}
        response = api_legal.get_legal()
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['datenschutz'], '')
        self.assertEqual(body['impressum'], '')


class TestPutLegal(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_legal.legal_texts_table = self.mock_table
        api_legal.members_table = self.mock_members_table

    def test_put_legal_saves_both_texts_as_superadmin(self):
        self.mock_members_table.get_item.return_value = {
            'Item': {'isSuperAdmin': True}
        }
        event = _event('PUT', '/legal', member_id=SUPER_ADMIN_ID, body={
            'datenschutz': 'Neuer Datenschutz',
            'impressum': 'Neues Impressum',
        })
        response = api_legal.put_legal(event)
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(self.mock_table.put_item.call_count, 2)

    def test_put_legal_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {
            'Item': {'isSuperAdmin': False}
        }
        event = _event('PUT', '/legal', member_id='user1', body={
            'datenschutz': 'x', 'impressum': 'y',
        })
        response = api_legal.put_legal(event)
        self.assertEqual(response['statusCode'], 403)
        self.mock_table.put_item.assert_not_called()


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_legal.py -v
```

Expected: `ModuleNotFoundError: No module named 'api_legal'`

- [ ] **Step 3: Implement api_legal.py**

Create `aws_backend/lambda/api_legal.py`:

```python
import json
import os

import boto3

dynamodb = boto3.resource('dynamodb')
legal_texts_table = dynamodb.Table(os.environ.get('LEGAL_TEXTS_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def get_legal():
    datenschutz = legal_texts_table.get_item(Key={'id': 'datenschutz'}).get('Item', {})
    impressum = legal_texts_table.get_item(Key={'id': 'impressum'}).get('Item', {})
    return {
        'statusCode': 200,
        'body': json.dumps({
            'datenschutz': datenschutz.get('text', ''),
            'impressum': impressum.get('text', ''),
        }),
    }


def put_legal(event):
    if not _is_superadmin(event):
        return _ERROR_403
    body = json.loads(event.get('body', '{}'))
    legal_texts_table.put_item(Item={'id': 'datenschutz', 'text': body.get('datenschutz', '')})
    legal_texts_table.put_item(Item={'id': 'impressum', 'text': body.get('impressum', '')})
    return {'statusCode': 200, 'body': json.dumps({'message': 'Gespeichert'})}


def handle_legal(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    if method == 'GET':
        return get_legal()
    elif method == 'PUT':
        return put_legal(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_legal.py -v
```

Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/api_legal.py aws_backend/lambda/tests/test_api_legal.py
git commit -m "feat: add api_legal for GET/PUT /legal"
```

---

## Task 3: Backend — api_news.py

**Files:**
- Create: `aws_backend/lambda/api_news.py`
- Create: `aws_backend/lambda/tests/test_api_news.py`

- [ ] **Step 1: Write failing tests**

Create `aws_backend/lambda/tests/test_api_news.py`:

```python
import json
import sys
import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timedelta

sys.modules.setdefault('boto3', MagicMock())
sys.path.insert(0, '.')
import api_news

APP_ID = 'app-123'
SUPER_ADMIN_ID = 'superadmin1'
FUTURE = (datetime.utcnow() + timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%S')
PAST = (datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%S')


def _event(method, path, member_id='user1', body=None, news_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': APP_ID, 'memberid': member_id},
        'pathParameters': {},
    }
    if news_id:
        event['pathParameters']['newsId'] = news_id
    if body:
        event['body'] = json.dumps(body)
    return event


class TestGetNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_news.news_table = self.mock_table

    def test_get_news_returns_non_expired_items(self):
        self.mock_table.scan.return_value = {
            'Items': [
                {'newsId': '1', 'title': 'Active', 'expiresAt': FUTURE},
                {'newsId': '2', 'title': 'Expired', 'expiresAt': PAST},
                {'newsId': '3', 'title': 'No expiry'},
            ]
        }
        response = api_news.get_news()
        body = json.loads(response['body'])
        titles = [i['title'] for i in body]
        self.assertIn('Active', titles)
        self.assertIn('No expiry', titles)
        self.assertNotIn('Expired', titles)

    def test_get_news_sorted_newest_first(self):
        self.mock_table.scan.return_value = {
            'Items': [
                {'newsId': '1', 'title': 'Old', 'date': '2026-01-01T00:00:00'},
                {'newsId': '2', 'title': 'New', 'date': '2026-06-01T00:00:00'},
            ]
        }
        response = api_news.get_news()
        body = json.loads(response['body'])
        self.assertEqual(body[0]['title'], 'New')


class TestPostNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_news.news_table = self.mock_table
        api_news.members_table = self.mock_members_table

    def test_post_news_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('POST', '/news', member_id='user1', body={'title': 'x', 'body': 'y'})
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 403)
        self.mock_table.put_item.assert_not_called()

    def test_post_news_saves_item_as_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/news', member_id=SUPER_ADMIN_ID, body={
            'title': 'Test', 'body': 'Text', 'expiresAt': FUTURE,
            'question': 'Wie findet ihr das?', 'questionOptions': ['Gut', 'Schlecht'],
        })
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['title'], 'Test')
        self.assertEqual(item['question'], 'Wie findet ihr das?')
        self.assertEqual(item['questionOptions'], ['Gut', 'Schlecht'])

    def test_post_news_without_optional_fields(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/news', member_id=SUPER_ADMIN_ID, body={'title': 'x', 'body': 'y'})
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 200)


class TestDeleteNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_news.news_table = self.mock_table
        api_news.members_table = self.mock_members_table

    def test_delete_news_as_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('DELETE', '/news/abc', member_id=SUPER_ADMIN_ID, news_id='abc')
        response = api_news.delete_news(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.delete_item.assert_called_once_with(Key={'newsId': 'abc'})

    def test_delete_news_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('DELETE', '/news/abc', member_id='user1', news_id='abc')
        response = api_news.delete_news(event)
        self.assertEqual(response['statusCode'], 403)


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_news.py -v
```

Expected: `ModuleNotFoundError: No module named 'api_news'`

- [ ] **Step 3: Implement api_news.py**

Create `aws_backend/lambda/api_news.py`:

```python
import json
import os
import uuid
from datetime import datetime

import boto3

dynamodb = boto3.resource('dynamodb')
news_table = dynamodb.Table(os.environ.get('NEWS_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def get_news():
    response = news_table.scan()
    items = response.get('Items', [])
    while 'LastEvaluatedKey' in response:
        response = news_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))

    now = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
    active = [i for i in items if not i.get('expiresAt') or i['expiresAt'] > now]
    active.sort(key=lambda i: i.get('date', ''), reverse=True)
    return {'statusCode': 200, 'body': json.dumps(active)}


def post_news(event):
    if not _is_superadmin(event):
        return _ERROR_403
    body = json.loads(event.get('body', '{}'))
    member_id = event.get('headers', {}).get('memberid', '')
    item = {
        'newsId': str(uuid.uuid4()),
        'title': body.get('title', ''),
        'body': body.get('body', ''),
        'date': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S'),
        'createdBy': member_id,
    }
    if body.get('expiresAt'):
        item['expiresAt'] = body['expiresAt']
    if body.get('question'):
        item['question'] = body['question']
    if body.get('questionOptions'):
        item['questionOptions'] = body['questionOptions']
    news_table.put_item(Item=item)
    return {'statusCode': 200, 'body': json.dumps(item)}


def delete_news(event):
    if not _is_superadmin(event):
        return _ERROR_403
    news_id = (event.get('pathParameters') or {}).get('newsId', '')
    news_table.delete_item(Key={'newsId': news_id})
    return {'statusCode': 200, 'body': json.dumps({'message': 'Gelöscht'})}


def handle_news(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    if method == 'GET' and path == '/news':
        return get_news()
    elif method == 'POST' and path == '/news':
        return post_news(event)
    elif method == 'DELETE' and path.startswith('/news/'):
        return delete_news(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_news.py -v
```

Expected: 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/api_news.py aws_backend/lambda/tests/test_api_news.py
git commit -m "feat: add api_news for GET/POST/DELETE /news with expiry filtering"
```

---

## Task 4: Backend — api_feedback.py

**Files:**
- Create: `aws_backend/lambda/api_feedback.py`
- Create: `aws_backend/lambda/tests/test_api_feedback.py`

- [ ] **Step 1: Write failing tests**

Create `aws_backend/lambda/tests/test_api_feedback.py`:

```python
import json
import sys
import unittest
from unittest.mock import MagicMock, patch, call

sys.modules.setdefault('boto3', MagicMock())
sys.modules.setdefault('push_notifications', MagicMock())
sys.path.insert(0, '.')
import api_feedback

APP_ID = 'app-123'
SUPER_ADMIN_APP_ID = 'app-super'
SUPER_ADMIN_MEMBER_ID = 'superadmin1'


def _event(method, path, member_id='user1', body=None, feedback_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': APP_ID, 'memberid': member_id},
        'pathParameters': {},
    }
    if feedback_id:
        event['pathParameters']['feedbackId'] = feedback_id
    if body:
        event['body'] = json.dumps(body)
    return event


class TestPostFeedback(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table
        api_feedback.SUPER_ADMIN_APPLICATION_ID = SUPER_ADMIN_APP_ID
        api_feedback.SUPER_ADMIN_MEMBER_ID = SUPER_ADMIN_MEMBER_ID
        api_feedback.ADMIN_EMAIL = 'test@example.com'

        self.mock_members_table.get_item.side_effect = lambda Key: {
            'Item': {'name': 'Max', 'memberId': Key['memberId'], 'token': 'fcm-token'}
        }

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_saves_item(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={'message': 'Test Feedback'})
        response = api_feedback.post_feedback(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['message'], 'Test Feedback')
        self.assertEqual(item['applicationId'], APP_ID)

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_sends_push_and_email(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={'message': 'Hi'})
        api_feedback.post_feedback(event)
        mock_push.assert_called_once()
        mock_email.assert_called_once()

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_stores_news_fields(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={
            'message': 'Juli',
            'newsId': 'news-1',
            'newsTitle': 'Terminplanung',
            'newsQuestion': 'Wann?',
        })
        api_feedback.post_feedback(event)
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['newsId'], 'news-1')
        self.assertEqual(item['newsQuestion'], 'Wann?')


class TestGetFeedback(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table

        self.items = [
            {'applicationId': APP_ID, 'feedbackId': '1', 'memberId': 'user1', 'message': 'Hello'},
            {'applicationId': APP_ID, 'feedbackId': '2', 'memberId': 'user2', 'message': 'World'},
        ]
        self.mock_table.query.return_value = {'Items': self.items}
        self.mock_table.scan.return_value = {'Items': self.items}

    def test_superadmin_gets_all_feedback(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('GET', '/feedback', member_id='superadmin1')
        response = api_feedback.get_feedback(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(len(body), 2)
        self.mock_table.scan.assert_called_once()

    def test_member_gets_only_own_feedback(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        self.mock_table.query.return_value = {
            'Items': [{'applicationId': APP_ID, 'feedbackId': '1', 'memberId': 'user1', 'message': 'Hello'}]
        }
        event = _event('GET', '/feedback', member_id='user1')
        response = api_feedback.get_feedback(event)
        body = json.loads(response['body'])
        self.assertEqual(len(body), 1)


class TestPostReply(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table

    def test_reply_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('POST', '/feedback/1/reply', member_id='user1',
                       body={'reply': 'Thanks'}, feedback_id='1')
        response = api_feedback.post_reply(event)
        self.assertEqual(response['statusCode'], 403)

    def test_reply_updates_feedback_item(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/feedback/1/reply', member_id='superadmin1',
                       body={'reply': 'Danke!', 'applicationId': APP_ID}, feedback_id='1')
        response = api_feedback.post_reply(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.update_item.assert_called_once()


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_feedback.py -v
```

Expected: `ModuleNotFoundError: No module named 'api_feedback'`

- [ ] **Step 3: Implement api_feedback.py**

Create `aws_backend/lambda/api_feedback.py`:

```python
import json
import os
import uuid
from datetime import datetime

import boto3
from boto3.dynamodb.conditions import Key, Attr
from push_notifications import send_push_notification

dynamodb = boto3.resource('dynamodb')
feedback_table = dynamodb.Table(os.environ.get('FEEDBACK_TABLE_NAME', ''))
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))

ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL', '')
SUPER_ADMIN_APPLICATION_ID = os.environ.get('SUPER_ADMIN_APPLICATION_ID', '')
SUPER_ADMIN_MEMBER_ID = os.environ.get('SUPER_ADMIN_MEMBER_ID', '')

_ERROR_403 = {'statusCode': 403, 'body': json.dumps({'error': 'Nicht berechtigt'})}


def _is_superadmin(event) -> bool:
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    item = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item')
    return bool(item and item.get('isSuperAdmin'))


def _send_ses_email(subject: str, body: str):
    if not ADMIN_EMAIL:
        return
    ses = boto3.client('ses', region_name='eu-central-1')
    ses.send_email(
        Source=ADMIN_EMAIL,
        Destination={'ToAddresses': [ADMIN_EMAIL]},
        Message={
            'Subject': {'Data': subject},
            'Body': {'Text': {'Data': body}},
        },
    )


def post_feedback(event):
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')
    body = json.loads(event.get('body', '{}'))

    member = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item', {})
    member_name = member.get('name', member_id)

    feedback_id = str(uuid.uuid4())
    item = {
        'applicationId': application_id,
        'feedbackId': feedback_id,
        'memberId': member_id,
        'memberName': member_name,
        'message': body.get('message', ''),
        'date': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S'),
    }
    if body.get('newsId'):
        item['newsId'] = body['newsId']
    if body.get('newsTitle'):
        item['newsTitle'] = body['newsTitle']
    if body.get('newsQuestion'):
        item['newsQuestion'] = body['newsQuestion']

    feedback_table.put_item(Item=item)

    # Push notification to SuperAdmin
    if SUPER_ADMIN_APPLICATION_ID and SUPER_ADMIN_MEMBER_ID:
        superadmin = members_table.get_item(
            Key={'applicationId': SUPER_ADMIN_APPLICATION_ID, 'memberId': SUPER_ADMIN_MEMBER_ID}
        ).get('Item', {})
        token = superadmin.get('token')
        if token:
            send_push_notification(
                token=token,
                notification={
                    'title': f'Feedback von {member_name}',
                    'body': body.get('message', '')[:100],
                    'url': '/info',
                    'type': 'feedback',
                },
                secret_name='firebase-credentials',
            )

    # Email to admin
    _send_ses_email(
        subject=f'Neues Feedback von {member_name} ({application_id})',
        body=f'Von: {member_name} ({member_id})\nVerein: {application_id}\n\n{body.get("message", "")}',
    )

    return {'statusCode': 200, 'body': json.dumps(item)}


def get_feedback(event):
    application_id = event.get('headers', {}).get('applicationid', '')
    member_id = event.get('headers', {}).get('memberid', '')

    member = members_table.get_item(
        Key={'applicationId': application_id, 'memberId': member_id}
    ).get('Item', {})
    is_superadmin = bool(member and member.get('isSuperAdmin'))

    if is_superadmin:
        response = feedback_table.scan()
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = feedback_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))
    else:
        response = feedback_table.query(
            KeyConditionExpression=Key('applicationId').eq(application_id),
            FilterExpression=Attr('memberId').eq(member_id),
        )
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = feedback_table.query(
                KeyConditionExpression=Key('applicationId').eq(application_id),
                FilterExpression=Attr('memberId').eq(member_id),
                ExclusiveStartKey=response['LastEvaluatedKey'],
            )
            items.extend(response.get('Items', []))

    items.sort(key=lambda i: i.get('date', ''), reverse=True)
    return {'statusCode': 200, 'body': json.dumps(items)}


def post_reply(event):
    if not _is_superadmin(event):
        return _ERROR_403
    feedback_id = (event.get('pathParameters') or {}).get('feedbackId', '')
    body = json.loads(event.get('body', '{}'))
    application_id = body.get('applicationId', '')
    reply_text = body.get('reply', '')
    replied_at = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')

    feedback_table.update_item(
        Key={'applicationId': application_id, 'feedbackId': feedback_id},
        UpdateExpression='SET reply = :r, repliedAt = :t',
        ExpressionAttributeValues={':r': reply_text, ':t': replied_at},
    )
    return {'statusCode': 200, 'body': json.dumps({'message': 'Antwort gespeichert'})}


def handle_feedback(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('requestContext', {}).get('http', {}).get('path')
    if method == 'POST' and path == '/feedback':
        return post_feedback(event)
    elif method == 'GET' and path == '/feedback':
        return get_feedback(event)
    elif method == 'POST' and '/reply' in path:
        return post_reply(event)
    return {'statusCode': 404, 'body': json.dumps({'error': 'Not found'})}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd aws_backend/lambda
python -m pytest tests/test_api_feedback.py -v
```

Expected: 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/api_feedback.py aws_backend/lambda/tests/test_api_feedback.py
git commit -m "feat: add api_feedback with push notification and SES email"
```

---

## Task 5: Wire Routes in lambda_handler.py

**Files:**
- Modify: `aws_backend/lambda/lambda_handler.py`

- [ ] **Step 1: Add imports and dispatch entries**

In `aws_backend/lambda/lambda_handler.py`, add these three imports at the top of the file alongside the existing handler imports:

```python
from api_legal import handle_legal
from api_news import handle_news
from api_feedback import handle_feedback
```

In the `_dispatch` function, add these entries **before** the final `return None` line:

```python
elif path.startswith('/news'):
    return {**headers, **handle_news(event, context)}
elif path.startswith('/feedback'):
    return {**headers, **handle_feedback(event, context)}
elif path.startswith('/legal'):
    return {**headers, **handle_legal(event, context)}
```

- [ ] **Step 2: Deploy the Lambda**

```bash
cd aws_backend/lambda
bash build.sh && bash update.sh
```

(Adjust to your actual deploy commands if different.)

- [ ] **Step 3: Smoke-test with curl**

```bash
# Replace BASE_URL, APP_ID, MEMBER_ID with real values
curl -s "$BASE_URL/legal" \
  -H "applicationId: $APP_ID" \
  -H "memberId: $MEMBER_ID" | jq .
# Expected: {"datenschutz": "", "impressum": ""}

curl -s "$BASE_URL/news" \
  -H "applicationId: $APP_ID" \
  -H "memberId: $MEMBER_ID" | jq .
# Expected: []
```

- [ ] **Step 4: Commit**

```bash
git add aws_backend/lambda/lambda_handler.py
git commit -m "feat: wire /news, /feedback and /legal routes in lambda_handler"
```

---

## Task 6: Flutter — legal_api.dart

**Files:**
- Create: `lib/api/legal_api.dart`

- [ ] **Step 1: Create legal_api.dart**

```dart
// lib/api/legal_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class LegalApi {
  final AppConfig config;
  final http.Client _client;

  LegalApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, String>> getLegal() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/legal'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return {
        'datenschutz': body['datenschutz'] as String? ?? '',
        'impressum': body['impressum'] as String? ?? '',
      };
    }
    throw Exception('Fehler beim Laden der Rechtstexte: ${response.statusCode}');
  }

  Future<void> putLegal({
    required String datenschutz,
    required String impressum,
  }) async {
    final response = await _client.put(
      Uri.parse('${config.apiBaseUrl}/legal'),
      headers: headers(config),
      body: json.encode({'datenschutz': datenschutz, 'impressum': impressum}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Speichern: ${response.statusCode}');
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/api/legal_api.dart
git commit -m "feat: add LegalApi Flutter client"
```

---

## Task 7: Flutter — news_api.dart

**Files:**
- Create: `lib/api/news_api.dart`

- [ ] **Step 1: Create news_api.dart**

```dart
// lib/api/news_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class NewsItem {
  final String newsId;
  final String title;
  final String body;
  final String date;
  final String? expiresAt;
  final String? question;
  final List<String>? questionOptions;

  NewsItem({
    required this.newsId,
    required this.title,
    required this.body,
    required this.date,
    this.expiresAt,
    this.question,
    this.questionOptions,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        newsId: json['newsId'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        date: json['date'] as String,
        expiresAt: json['expiresAt'] as String?,
        question: json['question'] as String?,
        questionOptions: json['questionOptions'] != null
            ? List<String>.from(json['questionOptions'] as List)
            : null,
      );
}

class NewsApi {
  final AppConfig config;
  final http.Client _client;

  NewsApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<NewsItem>> getNews() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/news'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Fehler beim Laden der Neuigkeiten: ${response.statusCode}');
  }

  Future<void> createNews({
    required String title,
    required String body,
    String? expiresAt,
    String? question,
    List<String>? questionOptions,
  }) async {
    final payload = <String, dynamic>{'title': title, 'body': body};
    if (expiresAt != null) payload['expiresAt'] = expiresAt;
    if (question != null) payload['question'] = question;
    if (questionOptions != null) payload['questionOptions'] = questionOptions;

    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/news'),
      headers: headers(config),
      body: json.encode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Erstellen: ${response.statusCode}');
    }
  }

  Future<void> deleteNews(String newsId) async {
    final response = await _client.delete(
      Uri.parse('${config.apiBaseUrl}/news/$newsId'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/api/news_api.dart
git commit -m "feat: add NewsApi Flutter client"
```

---

## Task 8: Flutter — feedback_api.dart

**Files:**
- Create: `lib/api/feedback_api.dart`

- [ ] **Step 1: Create feedback_api.dart**

```dart
// lib/api/feedback_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class FeedbackItem {
  final String applicationId;
  final String feedbackId;
  final String memberId;
  final String memberName;
  final String message;
  final String date;
  final String? newsId;
  final String? newsTitle;
  final String? newsQuestion;
  final String? reply;
  final String? repliedAt;

  FeedbackItem({
    required this.applicationId,
    required this.feedbackId,
    required this.memberId,
    required this.memberName,
    required this.message,
    required this.date,
    this.newsId,
    this.newsTitle,
    this.newsQuestion,
    this.reply,
    this.repliedAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) => FeedbackItem(
        applicationId: json['applicationId'] as String,
        feedbackId: json['feedbackId'] as String,
        memberId: json['memberId'] as String,
        memberName: json['memberName'] as String? ?? '',
        message: json['message'] as String,
        date: json['date'] as String,
        newsId: json['newsId'] as String?,
        newsTitle: json['newsTitle'] as String?,
        newsQuestion: json['newsQuestion'] as String?,
        reply: json['reply'] as String?,
        repliedAt: json['repliedAt'] as String?,
      );

  bool get hasReply => reply != null && reply!.isNotEmpty;
  bool get isFromNews => newsId != null;
}

class FeedbackApi {
  final AppConfig config;
  final http.Client _client;

  FeedbackApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<FeedbackItem>> getFeedback() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/feedback'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Fehler beim Laden: ${response.statusCode}');
  }

  Future<void> postFeedback({
    required String message,
    String? newsId,
    String? newsTitle,
    String? newsQuestion,
  }) async {
    final payload = <String, dynamic>{'message': message};
    if (newsId != null) payload['newsId'] = newsId;
    if (newsTitle != null) payload['newsTitle'] = newsTitle;
    if (newsQuestion != null) payload['newsQuestion'] = newsQuestion;

    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/feedback'),
      headers: headers(config),
      body: json.encode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Senden: ${response.statusCode}');
    }
  }

  Future<void> postReply({
    required String feedbackId,
    required String applicationId,
    required String reply,
  }) async {
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/feedback/$feedbackId/reply'),
      headers: headers(config),
      body: json.encode({'reply': reply, 'applicationId': applicationId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Antworten: ${response.statusCode}');
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/api/feedback_api.dart
git commit -m "feat: add FeedbackApi Flutter client"
```

---

## Task 9: Flutter — InfoFeedbackScreen skeleton + Tab 3 (Rechtliches)

Build the screen shell with `DefaultTabController` and implement the legal tab first — it has no state management complexity.

**Files:**
- Create: `lib/screens/info_feedback_screen.dart`

- [ ] **Step 1: Create the screen with Tab 3 (Rechtliches) working**

Create `lib/screens/info_feedback_screen.dart`:

```dart
// lib/screens/info_feedback_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feedback_api.dart';
import '../api/legal_api.dart';
import '../api/news_api.dart';
import '../config_loader.dart';
import '../models/member.dart';
import 'default_screen.dart';

class InfoFeedbackScreen extends DefaultScreen {
  const InfoFeedbackScreen({super.key, required super.config})
      : super(title: 'Info & Feedback');

  @override
  DefaultScreenState createState() => _InfoFeedbackScreenState();
}

class _InfoFeedbackScreenState extends DefaultScreenState<InfoFeedbackScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ℹ️ Info & Feedback'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '📰 News'),
              Tab(text: '💬 Feedback'),
              Tab(text: '📋 Rechtliches'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NewsTab(config: widget.config),
            _FeedbackTab(config: widget.config),
            _LegalTab(config: widget.config),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 3: Rechtliches ──────────────────────────────────────────────────────

class _LegalTab extends StatefulWidget {
  final AppConfig config;
  const _LegalTab({required this.config});

  @override
  State<_LegalTab> createState() => _LegalTabState();
}

class _LegalTabState extends State<_LegalTab> {
  bool _loading = true;
  String _datenschutz = '';
  String _impressum = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final texts = await LegalApi(widget.config).getLegal();
      if (!mounted) return;
      setState(() {
        _datenschutz = texts['datenschutz'] ?? '';
        _impressum = texts['impressum'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _edit(BuildContext context, Member member) async {
    final dsController = TextEditingController(text: _datenschutz);
    final imController = TextEditingController(text: _impressum);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechtstexte bearbeiten'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Datenschutzerklärung',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: dsController,
                  maxLines: 6,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Impressum',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: imController,
                  maxLines: 6,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;
    try {
      await LegalApi(widget.config).putLegal(
        datenschutz: dsController.text,
        impressum: imController.text,
      );
      setState(() {
        _datenschutz = dsController.text;
        _impressum = imController.text;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (member.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => _edit(context, member),
              icon: const Icon(Icons.edit),
              label: const Text('Texte bearbeiten'),
            ),
          ),
        _ExpandableSection(
          title: '🔒 Datenschutzerklärung',
          content: _datenschutz.isEmpty
              ? 'Noch kein Text hinterlegt.'
              : _datenschutz,
        ),
        const SizedBox(height: 8),
        _ExpandableSection(
          title: '📄 Impressum',
          content: _impressum.isEmpty ? 'Noch kein Text hinterlegt.' : _impressum,
        ),
      ],
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final String content;
  const _ExpandableSection({required this.title, required this.content});

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(widget.content,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

// ─── Tab 1 + 2 stubs (implemented in later tasks) ────────────────────────────

class _NewsTab extends StatelessWidget {
  final AppConfig config;
  const _NewsTab({required this.config});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('News — kommt gleich'));
}

class _FeedbackTab extends StatelessWidget {
  final AppConfig config;
  const _FeedbackTab({required this.config});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Feedback — kommt gleich'));
}
```

- [ ] **Step 2: Add tile to home_screen.dart and wire navigation**

In `lib/screens/home_screen.dart`, add the import at the top:

```dart
import 'info_feedback_screen.dart';
```

In `_buildGridMenu`, add this tile **after** all the `if (member.isAdmin)` and `if (member.isSuperAdmin)` tiles, as the last item in the `tiles` list (always visible to active members, no `_isScreenActive` check):

```dart
_buildMenuTile(
  context,
  'ℹ️ Info & Feedback',
  () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => InfoFeedbackScreen(config: widget.config),
    ),
  ),
),
```

- [ ] **Step 3: Run the app and verify Tab 3 works**

```bash
flutter run
```

Navigate to "ℹ️ Info & Feedback" → "📋 Rechtliches". Should load and show two expandable empty sections. SuperAdmin should see the edit button.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/info_feedback_screen.dart lib/screens/home_screen.dart
git commit -m "feat: add InfoFeedbackScreen shell with Rechtliches tab"
```

---

## Task 10: Flutter — Tab 1: Neuigkeiten

Replace the `_NewsTab` stub in `lib/screens/info_feedback_screen.dart`.

**Files:**
- Modify: `lib/screens/info_feedback_screen.dart`

- [ ] **Step 1: Replace _NewsTab stub with full implementation**

Replace the entire `_NewsTab` class (the stub at the bottom of the file) with:

```dart
// ─── Tab 1: Neuigkeiten ───────────────────────────────────────────────────────

class _NewsTab extends StatefulWidget {
  final AppConfig config;
  const _NewsTab({required this.config});

  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> {
  bool _loading = true;
  List<NewsItem> _items = [];
  // newsId -> true if this member already answered
  final Map<String, bool> _answered = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NewsApi(widget.config).getNews();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _delete(String newsId) async {
    try {
      await NewsApi(widget.config).deleteNews(newsId);
      setState(() => _items.removeWhere((i) => i.newsId == newsId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _submitAnswer(NewsItem item, String answer) async {
    try {
      await FeedbackApi(widget.config).postFeedback(
        message: answer,
        newsId: item.newsId,
        newsTitle: item.title,
        newsQuestion: item.question,
      );
      setState(() => _answered[item.newsId] = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final questionCtrl = TextEditingController();
    final optionCtrl = TextEditingController();
    String? expiresAt;
    bool useOptions = false;
    List<String> options = [];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Neuigkeit verfassen'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Titel', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Text', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sichtbar bis (optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _ExpiryChip(
                        label: '1 Woche',
                        selected: false,
                        onTap: () {
                          final d = DateTime.now().add(const Duration(days: 7));
                          setDlgState(() => expiresAt = d.toIso8601String());
                        },
                      ),
                      _ExpiryChip(
                        label: '1 Monat',
                        selected: false,
                        onTap: () {
                          final d = DateTime.now().add(const Duration(days: 30));
                          setDlgState(() => expiresAt = d.toIso8601String());
                        },
                      ),
                      _ExpiryChip(
                        label: '📅 Datum',
                        selected: false,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDlgState(() => expiresAt = picked.toIso8601String());
                          }
                        },
                      ),
                      _ExpiryChip(
                        label: '∞ Unbegrenzt',
                        selected: expiresAt == null,
                        onTap: () => setDlgState(() => expiresAt = null),
                      ),
                    ],
                  ),
                  if (expiresAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bis: ${expiresAt!.substring(0, 10)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('Frage (optional)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: questionCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Fragetext', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Antworttyp: '),
                      ChoiceChip(
                        label: const Text('Freitext'),
                        selected: !useOptions,
                        onSelected: (_) => setDlgState(() => useOptions = false),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Auswahloptionen'),
                        selected: useOptions,
                        onSelected: (_) => setDlgState(() => useOptions = true),
                      ),
                    ],
                  ),
                  if (useOptions) ...[
                    const SizedBox(height: 8),
                    ...options.asMap().entries.map((e) => ListTile(
                          dense: true,
                          title: Text(e.value),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setDlgState(() => options.removeAt(e.key)),
                          ),
                        )),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: optionCtrl,
                            decoration: const InputDecoration(
                                hintText: 'Option hinzufügen',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (optionCtrl.text.trim().isNotEmpty) {
                              setDlgState(() {
                                options.add(optionCtrl.text.trim());
                                optionCtrl.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  await NewsApi(widget.config).createNews(
                    title: titleCtrl.text.trim(),
                    body: bodyCtrl.text.trim(),
                    expiresAt: expiresAt,
                    question: questionCtrl.text.trim().isEmpty
                        ? null
                        : questionCtrl.text.trim(),
                    questionOptions:
                        useOptions && options.isNotEmpty ? options : null,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Fehler: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Veröffentlichen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (member.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Neuigkeit verfassen'),
            ),
          ),
        if (_items.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Keine Neuigkeiten'),
          )),
        ..._items.map((item) => _NewsCard(
              item: item,
              isSuperAdmin: member.isSuperAdmin,
              answered: _answered[item.newsId] ?? false,
              onDelete: () => _delete(item.newsId),
              onAnswer: (answer) => _submitAnswer(item, answer),
            )),
      ],
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label),
        backgroundColor: selected ? Theme.of(context).colorScheme.primary : null,
        labelStyle: TextStyle(color: selected ? Colors.white : null),
        onPressed: onTap,
      );
}

class _NewsCard extends StatefulWidget {
  final NewsItem item;
  final bool isSuperAdmin;
  final bool answered;
  final VoidCallback onDelete;
  final void Function(String answer) onAnswer;

  const _NewsCard({
    required this.item,
    required this.isSuperAdmin,
    required this.answered,
    required this.onDelete,
    required this.onAnswer,
  });

  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard> {
  final _answerCtrl = TextEditingController();
  String? _selectedOption;
  bool _submitted = false;

  bool get _hasQuestion => widget.item.question != null;
  bool get _hasOptions => widget.item.questionOptions?.isNotEmpty == true;
  bool get _alreadyAnswered => widget.answered || _submitted;

  void _submit() {
    final answer = _hasOptions ? _selectedOption : _answerCtrl.text.trim();
    if (answer == null || answer.isEmpty) return;
    widget.onAnswer(answer);
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.item.date.length >= 10
        ? widget.item.date.substring(0, 10)
        : widget.item.date;
    final hasQuestion = _hasQuestion;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasQuestion && !_alreadyAnswered
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(widget.item.body,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (hasQuestion) ...[
              const SizedBox(height: 10),
              if (_alreadyAnswered)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Deine Antwort gesendet: ${_selectedOption ?? _answerCtrl.text}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❓ ${widget.item.question}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple),
                      ),
                      const SizedBox(height: 8),
                      if (_hasOptions)
                        ...widget.item.questionOptions!.map((opt) => GestureDetector(
                              onTap: () => setState(() => _selectedOption = opt),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _selectedOption == opt
                                      ? Colors.purple.shade100
                                      : Colors.white,
                                  border: Border.all(
                                    color: _selectedOption == opt
                                        ? Colors.purple
                                        : Colors.purple.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(opt,
                                    style: TextStyle(
                                      fontWeight: _selectedOption == opt
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    )),
                              ),
                            ))
                      else
                        TextField(
                          controller: _answerCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Deine Antwort...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
                          child: const Text('Antwort senden'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (widget.isSuperAdmin)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Löschen', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the app and test Tab 1**

```bash
flutter run
```

- Navigate to "ℹ️ Info & Feedback" → "📰 News"
- As SuperAdmin: tap "Neuigkeit verfassen", fill in title + body, set expiry, add optional question with options, tap "Veröffentlichen"
- News card should appear. Tapping an option and "Antwort senden" should send to feedback

- [ ] **Step 3: Commit**

```bash
git add lib/screens/info_feedback_screen.dart
git commit -m "feat: implement News tab with create/delete and question/answer support"
```

---

## Task 11: Flutter — Tab 2: Feedback

Replace the `_FeedbackTab` stub in `lib/screens/info_feedback_screen.dart`.

**Files:**
- Modify: `lib/screens/info_feedback_screen.dart`

- [ ] **Step 1: Replace _FeedbackTab stub with full implementation**

Replace the `_FeedbackTab` class at the bottom of `lib/screens/info_feedback_screen.dart` with:

```dart
// ─── Tab 2: Feedback ─────────────────────────────────────────────────────────

class _FeedbackTab extends StatefulWidget {
  final AppConfig config;
  const _FeedbackTab({required this.config});

  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  bool _loading = true;
  List<FeedbackItem> _items = [];
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await FeedbackApi(widget.config).getFeedback();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _send() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FeedbackApi(widget.config).postFeedback(message: msg);
      _messageCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(FeedbackItem item, String replyText) async {
    try {
      await FeedbackApi(widget.config).postReply(
        feedbackId: item.feedbackId,
        applicationId: item.applicationId,
        reply: replyText,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = Provider.of<Member>(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (member.isSuperAdmin) return _buildSuperAdminView(context);
    return _buildMemberView(context);
  }

  Widget _buildMemberView(BuildContext context) {
    final own = _items
        .where((i) => i.memberId == widget.config.memberId)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _messageCtrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Deine Nachricht an den Admin...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('📤 Feedback senden'),
          ),
        ),
        if (own.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Deine bisherigen Nachrichten',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...own.map((item) => _MemberFeedbackCard(item: item)),
        ],
      ],
    );
  }

  Widget _buildSuperAdminView(BuildContext context) {
    final open = _items.where((i) => !i.hasReply).toList();
    final answered = _items.where((i) => i.hasReply).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            _StatusChip(label: '${open.length} offen', color: Colors.red),
            const SizedBox(width: 8),
            _StatusChip(label: '${answered.length} beantwortet', color: Colors.green),
          ],
        ),
        const SizedBox(height: 12),
        ...open.map((item) => _AdminFeedbackCard(
              item: item,
              isOpen: true,
              onReply: (text) => _reply(item, text),
            )),
        ...answered.map((item) => _AdminFeedbackCard(
              item: item,
              isOpen: false,
              onReply: (text) => _reply(item, text),
            )),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text('● $label',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      );
}

class _MemberFeedbackCard extends StatelessWidget {
  final FeedbackItem item;
  const _MemberFeedbackCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateStr = item.date.length >= 10 ? item.date.substring(0, 10) : item.date;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.isFromNews ? Colors.purple.shade50 : Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isFromNews)
                  Text(
                    '❓ Antwort auf: "${item.newsQuestion ?? item.newsTitle}"',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade700,
                        fontWeight: FontWeight.w500),
                  ),
                if (item.isFromNews) const SizedBox(height: 4),
                Text('Du · $dateStr',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(item.message),
              ],
            ),
          ),
          if (item.hasReply)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '↩️ Antwort vom Admin · ${item.repliedAt?.substring(0, 10) ?? ''}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(item.reply ?? ''),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminFeedbackCard extends StatefulWidget {
  final FeedbackItem item;
  final bool isOpen;
  final void Function(String reply) onReply;

  const _AdminFeedbackCard({
    required this.item,
    required this.isOpen,
    required this.onReply,
  });

  @override
  State<_AdminFeedbackCard> createState() => _AdminFeedbackCardState();
}

class _AdminFeedbackCardState extends State<_AdminFeedbackCard> {
  final _replyCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dateStr = item.date.length >= 10 ? item.date.substring(0, 10) : item.date;
    final borderColor = widget.isOpen ? Colors.red.shade200 : Colors.green.shade200;
    final bgColor = widget.isOpen ? const Color(0xFFFFF8F8) : const Color(0xFFF9FFF9);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.isOpen ? "⚠️" : "✅"} ${item.memberName} · ${item.applicationId} · $dateStr',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: widget.isOpen ? Colors.red.shade800 : Colors.green.shade800,
                  ),
                ),
                if (item.isFromNews) ...[
                  const SizedBox(height: 2),
                  Text(
                    '❓ "${item.newsQuestion ?? item.newsTitle}"',
                    style: TextStyle(
                        fontSize: 11, color: Colors.purple.shade700),
                  ),
                ],
                const SizedBox(height: 4),
                Text(item.message),
              ],
            ),
          ),
          if (item.hasReply)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '↩️ Deine Antwort · ${item.repliedAt?.substring(0, 10) ?? ''}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(item.reply ?? ''),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _replyCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Antwort schreiben...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_replyCtrl.text.trim().isEmpty) return;
                        widget.onReply(_replyCtrl.text.trim());
                      },
                      child: const Text('↩️ Antworten'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run the app and test Tab 2**

```bash
flutter run
```

- As a regular member: send a feedback, verify it appears in the list
- As SuperAdmin: see all feedback color-coded, reply to an open one
- Refresh: replied item should turn green

- [ ] **Step 3: Commit**

```bash
git add lib/screens/info_feedback_screen.dart
git commit -m "feat: implement Feedback tab with member history and SuperAdmin reply view"
```

---

## Task 12: Cleanup

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add .superpowers/ to .gitignore**

Add to `.gitignore`:

```
# Brainstorming visual companion
.superpowers/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore .superpowers/ directory"
```

---

## Self-Review Checklist

| Spec requirement | Task |
|---|---|
| Tab 1 — News (SuperAdmin publishes, all read) | Task 3, 7, 10 |
| News expiry (chips + datepicker) | Task 3, 10 |
| News optional question (free text) | Task 3, 7, 10 |
| News optional question (predefined options) | Task 3, 7, 10 |
| One answer per member per question | Task 3 (backend enforces via feedbackId+newsId; Flutter hides form after submit) |
| Tab 2 — Member sends feedback | Task 4, 8, 11 |
| Member sees own feedback history | Task 4, 8, 11 |
| Member sees replies (no "waiting" label) | Task 11 |
| News-question answers in member feedback list | Task 11 |
| SuperAdmin sees all feedback, color-coded | Task 4, 8, 11 |
| SuperAdmin can reply | Task 4, 8, 11 |
| Push notification to SuperAdmin on new feedback | Task 4 |
| Email (SES) to admin on new feedback | Task 4 |
| Tab 3 — Datenschutzerklärung + Impressum | Task 2, 6, 9 |
| SuperAdmin can edit legal texts | Task 2, 6, 9 |
| Legal texts global, no app deployment | Task 2, 6, 9 |
| Screen always visible (no active_screens gate) | Task 9 |
| DynamoDB tables + env vars | Task 1 |
| SES setup | Task 1 |
| .gitignore for .superpowers | Task 12 |
