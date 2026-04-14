# Calendar Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each member can opt-in to FCM push reminders for calendar events and choose how far in advance (2h/6h/24h/48h); an hourly AWS Lambda sends the notifications.

**Architecture:** Two new fields on `Member` (Dart + DynamoDB); a Flutter settings dialog in `CalendarScreen`; a new `api_reminders.py` Lambda triggered hourly via EventBridge that reads the cached ICS, matches events to member preferences, and sends FCM notifications with DynamoDB-TTL deduplication.

**Tech Stack:** Flutter/Dart, Python 3.10, AWS Lambda, DynamoDB, EventBridge, Firebase FCM (existing `push_notifications.py`), dateutil (already in Lambda zip)

**Spec:** `docs/specs/2026-04-14-calendar-reminders-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `lib/config_loader.dart` | Member: +2 fields, updateMember, encodeMember |
| Modify | `test/unit/config_loader_test.dart` | +5 tests for reminder fields |
| Modify | `lib/screens/calendar_screen.dart` | AppBar gear icon + settings dialog |
| Create | `aws_backend/lambda/api_reminders.py` | ICS parsing + reminder check logic |
| Create | `aws_backend/lambda/reminder_handler.py` | Lambda entry point for EventBridge |
| Create | `aws_backend/lambda/tests/test_api_reminders.py` | Python unit tests |
| Create | `aws_backend/api_reminders.tf` | DynamoDB table + Lambda + EventBridge |

---

## Task 1: Member – reminder fields (Dart)

**Files:**
- Modify: `lib/config_loader.dart`
- Modify: `test/unit/config_loader_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `test/unit/config_loader_test.dart` inside the existing `group('Member', ...)` block:

```dart
test('updateMember sets reminderEnabled from JSON', () {
  final config = AppConfig(
    apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
  );
  config.member.updateMember({'reminderEnabled': false, 'reminderHoursBefore': 6});
  expect(config.member.reminderEnabled, false);
  expect(config.member.reminderHoursBefore, 6);
});

test('updateMember uses defaults when reminder fields absent', () {
  final config = AppConfig(
    apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
  );
  config.member.updateMember({'name': 'X'});
  expect(config.member.reminderEnabled, true);
  expect(config.member.reminderHoursBefore, 24);
});

test('encodeMember includes reminderEnabled and reminderHoursBefore', () {
  final config = AppConfig(
    apiBaseUrl: 'http://x', applicationId: 'a', memberId: 'm',
  );
  config.member.updateMember({'reminderEnabled': false, 'reminderHoursBefore': 48});
  final json = jsonDecode(config.member.encodeMember());
  expect(json['reminderEnabled'], false);
  expect(json['reminderHoursBefore'], 48);
});
```

- [ ] **Step 2: Run tests – expect failure**

```bash
flutter test test/unit/config_loader_test.dart
```

Expected: `getter 'reminderEnabled' not found` or similar.

- [ ] **Step 3: Add fields to Member class in `lib/config_loader.dart`**

After `String _phone2 = '';` add:

```dart
bool _reminderEnabled = true;
int _reminderHoursBefore = 24;
```

After the existing getters, add:

```dart
bool get reminderEnabled => _reminderEnabled;
int get reminderHoursBefore => _reminderHoursBefore;
set reminderEnabled(bool v) => _reminderEnabled = v;
set reminderHoursBefore(int v) => _reminderHoursBefore = v;
```

In `updateMember()`, before `notifyListeners();` add:

```dart
_reminderEnabled = member?['reminderEnabled'] ?? true;
_reminderHoursBefore = member?['reminderHoursBefore'] ?? 24;
```

In `encodeMember()`, inside the `jsonEncode({...})` map add:

```dart
'reminderEnabled': _reminderEnabled,
'reminderHoursBefore': _reminderHoursBefore,
```

- [ ] **Step 4: Run tests – expect pass**

```bash
flutter test test/unit/config_loader_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/config_loader.dart test/unit/config_loader_test.dart
git commit -m "feat: add reminderEnabled and reminderHoursBefore to Member"
```

---

## Task 2: CalendarScreen – settings dialog

**Files:**
- Modify: `lib/screens/calendar_screen.dart`

No automated test for this task – the dialog is verified manually (see step 3).

- [ ] **Step 1: Add `_showReminderSettings` method to `_CalendarScreenState`**

Add this method anywhere inside `_CalendarScreenState`:

```dart
Future<void> _showReminderSettings() async {
  bool enabled = widget.config.member.reminderEnabled;
  int hoursBefore = widget.config.member.reminderHoursBefore;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Erinnerungseinstellungen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Erinnerungen aktivieren'),
              value: enabled,
              onChanged: (v) => setDialogState(() => enabled = v),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              for (final entry in const {
                2: '2 Stunden',
                6: '6 Stunden',
                24: '1 Tag',
                48: '2 Tage',
              }.entries)
                RadioListTile<int>(
                  title: Text(entry.value),
                  value: entry.key,
                  groupValue: hoursBefore,
                  onChanged: (v) => setDialogState(() => hoursBefore = v!),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              widget.config.member.reminderEnabled = enabled;
              widget.config.member.reminderHoursBefore = hoursBefore;
              try {
                await widget.config.member.saveMember();
                if (mounted) {
                  Navigator.pop(ctx);
                  showInfo('Einstellungen gespeichert');
                }
              } catch (e) {
                if (mounted) showError('Fehler beim Speichern: $e');
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Add gear icon to AppBar**

Replace the existing `appBar:` line in `build()`:

```dart
appBar: AppBar(
  title: const Text('📅 Termine'),
  actions: [
    IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Erinnerungseinstellungen',
      onPressed: _showReminderSettings,
    ),
  ],
),
```

- [ ] **Step 3: Verify manually**

```bash
flutter run -d chrome
```

Navigate to Termine → tap ⚙️ → toggle on/off → change time → Speichern. Check network tab for POST to `/members`.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/calendar_screen.dart
git commit -m "feat: add reminder settings dialog to CalendarScreen"
```

---

## Task 3: Python – ICS parsing

**Files:**
- Create: `aws_backend/lambda/api_reminders.py`
- Create: `aws_backend/lambda/tests/test_api_reminders.py`

- [ ] **Step 1: Write failing tests for `parse_events`**

Create `aws_backend/lambda/tests/test_api_reminders.py`:

```python
import sys
import os
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from api_reminders import parse_events


SAMPLE_ICS = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:abc123@example.com
DTSTART;TZID=Europe/Berlin:20260501T190000
SUMMARY:Vereinsabend
END:VEVENT
BEGIN:VEVENT
UID:def456@example.com
DTSTART:20260602T170000Z
SUMMARY:Jahreshauptversammlung
END:VEVENT
END:VCALENDAR"""

INCOMPLETE_VEVENT = """BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20260501T190000Z
SUMMARY:Kein UID
END:VEVENT
END:VCALENDAR"""


class TestParseEvents(unittest.TestCase):
    def test_empty_string_returns_empty_list(self):
        self.assertEqual(parse_events(''), [])

    def test_parses_two_events(self):
        events = parse_events(SAMPLE_ICS)
        self.assertEqual(len(events), 2)

    def test_event_has_uid_summary_dtstart(self):
        events = parse_events(SAMPLE_ICS)
        self.assertEqual(events[0]['uid'], 'abc123@example.com')
        self.assertEqual(events[0]['summary'], 'Vereinsabend')
        self.assertIsInstance(events[0]['dtstart'], datetime)

    def test_dtstart_with_tzid_is_utc(self):
        events = parse_events(SAMPLE_ICS)
        self.assertEqual(events[0]['dtstart'].tzinfo, timezone.utc)

    def test_dtstart_z_suffix_is_utc(self):
        events = parse_events(SAMPLE_ICS)
        self.assertEqual(events[1]['dtstart'].tzinfo, timezone.utc)

    def test_event_without_uid_is_skipped(self):
        events = parse_events(INCOMPLETE_VEVENT)
        self.assertEqual(len(events), 0)


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run – expect failure**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_reminders.py -v
```

Expected: `ModuleNotFoundError: No module named 'api_reminders'`

- [ ] **Step 3: Implement `parse_events` in new `api_reminders.py`**

Create `aws_backend/lambda/api_reminders.py`:

```python
import json
import os
import re
from datetime import datetime, timezone, timedelta

import boto3
from dateutil import parser as dateutil_parser
from dateutil.tz import gettz

from push_notifications import send_push_notification


# ── ICS parsing ──────────────────────────────────────────────────────────────

def parse_events(ics_content: str) -> list:
    """Parse VEVENT blocks from an ICS string.

    Returns a list of dicts with keys: uid (str), summary (str), dtstart (datetime UTC-aware).
    Events missing uid, summary, or dtstart are skipped.
    """
    events = []
    current = {}
    in_event = False

    for raw_line in ics_content.splitlines():
        line = raw_line.rstrip('\r')

        if line == 'BEGIN:VEVENT':
            in_event = True
            current = {}
        elif line == 'END:VEVENT':
            in_event = False
            if 'uid' in current and 'dtstart' in current and 'summary' in current:
                events.append(current)
        elif in_event:
            if line.startswith('UID:'):
                current['uid'] = line[4:].strip()
            elif line.upper().startswith('DTSTART'):
                header, _, value = line.partition(':')
                tzid_match = re.search(r'TZID=([^;:]+)', header)
                tzid = tzid_match.group(1) if tzid_match else None
                try:
                    dt = dateutil_parser.parse(value.strip())
                    if tzid and dt.tzinfo is None:
                        tz = gettz(tzid)
                        if tz:
                            dt = dt.replace(tzinfo=tz)
                    elif dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    current['dtstart'] = dt.astimezone(timezone.utc)
                except Exception:
                    pass
            elif line.startswith('SUMMARY:'):
                current['summary'] = line[8:].strip()

    return events
```

- [ ] **Step 4: Run – expect pass**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_reminders.py -v
```

Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add aws_backend/lambda/api_reminders.py aws_backend/lambda/tests/test_api_reminders.py
git commit -m "feat: add ICS parser in api_reminders.py"
```

---

## Task 4: Python – check_reminders

**Files:**
- Modify: `aws_backend/lambda/api_reminders.py` (add `_get_ics_content`, `check_reminders`)
- Create: `aws_backend/lambda/reminder_handler.py`
- Modify: `aws_backend/lambda/tests/test_api_reminders.py` (add integration tests)

- [ ] **Step 1: Write failing tests for `check_reminders`**

Append to `aws_backend/lambda/tests/test_api_reminders.py`:

```python
import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone, timedelta


# ── Fixtures ────────────────────────────────────────────────────────────────

def _make_ics(uid: str, hours_from_now: float, summary: str = 'Test') -> str:
    dt = datetime.now(timezone.utc) + timedelta(hours=hours_from_now)
    dtstart = dt.strftime('%Y%m%dT%H%M%SZ')
    return (
        f'BEGIN:VCALENDAR\nBEGIN:VEVENT\n'
        f'UID:{uid}\nDTSTART:{dtstart}\nSUMMARY:{summary}\n'
        f'END:VEVENT\nEND:VCALENDAR'
    )


def _make_member(token='tok', enabled=True, hours=24) -> dict:
    return {
        'memberId': 'm1',
        'token': token,
        'reminderEnabled': enabled,
        'reminderHoursBefore': hours,
    }


class TestCheckReminders(unittest.TestCase):
    def setUp(self):
        import api_reminders
        self.mod = api_reminders

        self.members_table = MagicMock()
        self.reminders_table = MagicMock()
        self.reminders_table.get_item.return_value = {}  # no dedup hit

        self.mod.members_table = self.members_table
        self.mod.reminders_table = self.reminders_table
        self.mod.s3_client = MagicMock()
        self.mod.send_push_notification = MagicMock(
            return_value={'status_code': 200, 'response': {}}
        )

    def _run(self, ics: str, members: list):
        self.mod.s3_client.get_object.return_value = {
            'Body': MagicMock(read=lambda: ics.encode())
        }
        self.members_table.scan.return_value = {'Items': members}
        import importlib
        return self.mod.check_reminders({}, {})

    def test_sends_notification_when_event_in_window(self):
        ics = _make_ics('uid1', hours_from_now=23.5)  # in [23,24)
        self._run(ics, [_make_member(hours=24)])
        self.mod.send_push_notification.assert_called_once()

    def test_no_notification_outside_window(self):
        ics = _make_ics('uid2', hours_from_now=22.0)  # not in [23,24)
        self._run(ics, [_make_member(hours=24)])
        self.mod.send_push_notification.assert_not_called()

    def test_no_notification_when_disabled(self):
        ics = _make_ics('uid3', hours_from_now=23.5)
        self._run(ics, [_make_member(enabled=False)])
        self.mod.send_push_notification.assert_not_called()

    def test_no_notification_without_token(self):
        ics = _make_ics('uid4', hours_from_now=23.5)
        self._run(ics, [_make_member(token='')])
        self.mod.send_push_notification.assert_not_called()

    def test_no_notification_when_dedup_hit(self):
        ics = _make_ics('uid5', hours_from_now=23.5)
        self.reminders_table.get_item.return_value = {'Item': {'memberId': 'm1', 'eventId': 'uid5'}}
        self._run(ics, [_make_member(hours=24)])
        self.mod.send_push_notification.assert_not_called()

    def test_writes_dedup_entry_after_sending(self):
        ics = _make_ics('uid6', hours_from_now=23.5)
        self._run(ics, [_make_member(hours=24)])
        self.reminders_table.put_item.assert_called_once()
        call_kwargs = self.reminders_table.put_item.call_args[1]['Item']
        self.assertEqual(call_kwargs['memberId'], 'm1')
        self.assertEqual(call_kwargs['eventId'], 'uid6')
        self.assertIn('ttl', call_kwargs)

    def test_returns_200(self):
        ics = _make_ics('uid7', hours_from_now=23.5)
        result = self._run(ics, [_make_member(hours=24)])
        self.assertEqual(result['statusCode'], 200)
```

- [ ] **Step 2: Run – expect failure**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_reminders.py::TestCheckReminders -v
```

Expected: `AttributeError: module 'api_reminders' has no attribute 'check_reminders'`

- [ ] **Step 3: Implement `check_reminders` in `api_reminders.py`**

Append to `aws_backend/lambda/api_reminders.py` (below `parse_events`):

```python
# ── Module-level resources (replaced in tests) ───────────────────────────────

_dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

members_table = _dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))
reminders_table = _dynamodb.Table(os.environ.get('REMINDERS_TABLE_NAME', ''))

_FIREBASE_SECRET = os.environ.get('FIREBASE_SECRET_NAME', 'firebase-credentials')


# ── S3 helper ─────────────────────────────────────────────────────────────────

def _get_ics_content() -> str:
    date = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    key = f'calendar/calendar_{date}.ics'
    bucket = os.environ.get('S3_BUCKET_NAME', '')
    obj = s3_client.get_object(Bucket=bucket, Key=key)
    return obj['Body'].read().decode('utf-8')


# ── Lambda handler ────────────────────────────────────────────────────────────

def check_reminders(event, context):
    try:
        ics_content = _get_ics_content()
    except Exception as e:
        print(f'Failed to load ICS from S3: {e}')
        return {'statusCode': 500, 'body': f'ICS load failed: {e}'}

    events = parse_events(ics_content)
    if not events:
        print('No events in ICS')
        return {'statusCode': 200, 'body': 'no events'}

    now = datetime.now(timezone.utc)
    members_resp = members_table.scan()
    members = members_resp.get('Items', [])

    for member in members:
        token = member.get('token', '')
        if not token:
            continue
        if not member.get('reminderEnabled', True):
            continue

        hours_before = int(member.get('reminderHoursBefore', 24))
        member_id = member['memberId']

        for ev in events:
            hours_until = (ev['dtstart'] - now).total_seconds() / 3600
            if not (hours_before - 1 <= hours_until < hours_before):
                continue

            uid = ev['uid']

            try:
                hit = reminders_table.get_item(Key={'memberId': member_id, 'eventId': uid})
                if 'Item' in hit:
                    print(f'Already sent: {member_id}/{uid}')
                    continue
            except Exception as e:
                print(f'Dedup check error: {e}')
                continue

            dt_str = ev['dtstart'].strftime('%d.%m.%Y %H:%M Uhr')
            send_push_notification(
                token=token,
                notification={
                    'title': f'Erinnerung: {ev["summary"]}',
                    'body': f'Termin am {dt_str}',
                    'type': 'reminder',
                },
                secret_name=_FIREBASE_SECRET,
            )
            print(f'Notification sent: {member_id}/{uid}')

            ttl = int((ev['dtstart'] + timedelta(days=7)).timestamp())
            reminders_table.put_item(Item={
                'memberId': member_id,
                'eventId': uid,
                'ttl': ttl,
            })

    return {'statusCode': 200, 'body': 'done'}
```

- [ ] **Step 4: Create `reminder_handler.py`**

Create `aws_backend/lambda/reminder_handler.py`:

```python
from api_reminders import check_reminders


def lambda_handler(event, context):
    return check_reminders(event, context)
```

- [ ] **Step 5: Run all reminder tests – expect pass**

```bash
cd aws_backend/lambda && python -m pytest tests/test_api_reminders.py -v
```

Expected: all 13 tests pass.

- [ ] **Step 6: Run full Python test suite**

```bash
cd aws_backend/lambda && python -m pytest tests/ -v
```

Expected: all tests pass (no regressions).

- [ ] **Step 7: Commit**

```bash
git add aws_backend/lambda/api_reminders.py aws_backend/lambda/reminder_handler.py aws_backend/lambda/tests/test_api_reminders.py
git commit -m "feat: add check_reminders Lambda handler with dedup"
```

---

## Task 5: Terraform – DynamoDB + Lambda + EventBridge

**Files:**
- Create: `aws_backend/api_reminders.tf`

The reminder Lambda uses the same IAM role (`aws_iam_role.lambda_role`) and the same zip (`lambda/lambda.zip`) as the existing backend Lambda. The zip already contains all lambda code including `api_reminders.py` and `reminder_handler.py` after the next `build.sh` run.

- [ ] **Step 1: Create `aws_backend/api_reminders.tf`**

```hcl
# DynamoDB table for deduplication
resource "aws_dynamodb_table" "reminders_sent_table" {
    name         = "${local.name_prefix}-reminders_sent"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "memberId"
    range_key    = "eventId"

    attribute {
        name = "memberId"
        type = "S"
    }
    attribute {
        name = "eventId"
        type = "S"
    }

    ttl {
        attribute_name = "ttl"
        enabled        = true
    }
}

# Lambda function for reminders (separate from API Lambda to avoid timeout issues)
resource "aws_lambda_function" "lambda_reminders" {
    function_name = "${local.name_prefix}-lambda_reminders"
    role          = aws_iam_role.lambda_role.arn
    handler       = "reminder_handler.lambda_handler"
    runtime       = "python3.10"
    filename      = "lambda/lambda.zip"
    timeout       = 300

    environment {
        variables = {
            MEMBERS_TABLE_NAME   = aws_dynamodb_table.members_table.name
            REMINDERS_TABLE_NAME = aws_dynamodb_table.reminders_sent_table.name
            S3_BUCKET_NAME       = aws_s3_bucket.s3_bucket.bucket
            FIREBASE_SECRET_NAME = aws_secretsmanager_secret.firebase_credentials.name
        }
    }
}

# EventBridge rule – every hour
resource "aws_cloudwatch_event_rule" "reminders_hourly" {
    name                = "${local.name_prefix}-reminders-hourly"
    schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "reminders_target" {
    rule      = aws_cloudwatch_event_rule.reminders_hourly.name
    target_id = "lambda_reminders"
    arn       = aws_lambda_function.lambda_reminders.arn
}

resource "aws_lambda_permission" "eventbridge_reminders" {
    statement_id  = "AllowEventBridgeInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_reminders.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.reminders_hourly.arn
}
```

- [ ] **Step 2: Check which table resource name the `members_table` uses**

```bash
grep 'resource "aws_dynamodb_table"' aws_backend/lambda_backend.tf aws_backend/api_members.tf
```

Verify the members table resource is named `aws_dynamodb_table.members_table`. Adjust the `MEMBERS_TABLE_NAME` reference in `api_reminders.tf` if different.

- [ ] **Step 3: Rebuild Lambda zip**

```bash
cd aws_backend && bash build.sh
```

Verify `lambda/lambda.zip` is updated (check timestamp).

- [ ] **Step 4: Apply Terraform**

```bash
cd aws_backend && terraform init && terraform plan
```

Review plan: should show +4 resources (DynamoDB table, Lambda, EventBridge rule, EventBridge target, Lambda permission).

```bash
terraform apply
```

- [ ] **Step 5: Manual smoke test**

Invoke the reminder Lambda manually with an empty event to verify it runs without errors:

```bash
aws lambda invoke \
  --function-name $(terraform output -raw name_prefix)-lambda_reminders \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/reminder_response.json && cat /tmp/reminder_response.json
```

Expected: `{"statusCode": 200, "body": "done"}` or `"no events"` (if no events in ICS today).

Check CloudWatch logs for any errors:

```bash
aws logs tail /aws/lambda/$(terraform output -raw name_prefix)-lambda_reminders --since 5m
```

- [ ] **Step 6: Commit**

```bash
git add aws_backend/api_reminders.tf
git commit -m "feat: add reminders DynamoDB table, Lambda and EventBridge rule"
```

---

## Task 6: CLAUDE.md – mark TODO done

- [ ] **Step 1: Mark item as done in `CLAUDE.md`**

In `.claude/CLAUDE.md`, change:

```
- [ ] Erinnerungsbenachrichtigung X Stunden vor einem Termin
```

to:

```
- [x] Erinnerungsbenachrichtigung X Stunden vor einem Termin
```

- [ ] **Step 2: Commit**

```bash
git add .claude/CLAUDE.md
git commit -m "docs: mark calendar reminder TODO as done"
```
