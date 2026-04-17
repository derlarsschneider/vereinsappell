import sys
import os
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, patch

# Pre-patch modules that api_reminders imports at module level
sys.modules.setdefault('boto3', MagicMock())
sys.modules.setdefault('push_notifications', MagicMock())

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

    def test_crlf_line_endings_are_handled(self):
        ics = (
            'BEGIN:VCALENDAR\r\n'
            'BEGIN:VEVENT\r\n'
            'UID:crlf@example.com\r\n'
            'DTSTART:20260501T190000Z\r\n'
            'SUMMARY:CRLF Test\r\n'
            'END:VEVENT\r\n'
            'END:VCALENDAR'
        )
        events = parse_events(ics)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['uid'], 'crlf@example.com')

    def test_malformed_dtstart_skips_event(self):
        ics = (
            'BEGIN:VCALENDAR\n'
            'BEGIN:VEVENT\n'
            'UID:bad-date@example.com\n'
            'DTSTART:NOT-A-DATE\n'
            'SUMMARY:Bad Date\n'
            'END:VEVENT\n'
            'END:VCALENDAR'
        )
        events = parse_events(ics)
        self.assertEqual(len(events), 0)


if __name__ == '__main__':
    unittest.main()


# ── Fixtures ──────────────────────────────────────────────────────────────────

APP_ID = 'app-123'


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
        'applicationId': APP_ID,
        'memberId': 'm1',
        'token': token,
        'reminderEnabled': enabled,
        'reminderHoursBefore': hours,
    }


class TestCheckReminders(unittest.TestCase):
    def setUp(self):
        import api_reminders
        self.mod = api_reminders

        self.members_table   = MagicMock()
        self.reminders_table = MagicMock()
        self.customers_table = MagicMock()
        self.reminders_table.get_item.return_value = {}  # no dedup hit

        self.mod.members_table   = self.members_table
        self.mod.reminders_table = self.reminders_table
        self.mod.customers_table = self.customers_table
        self.mod.s3_client = MagicMock()
        self.mod.send_push_notification = MagicMock(
            return_value={'status_code': 200, 'response': {}}
        )

    def _run(self, ics: str, members: list):
        self.mod.s3_client.get_object.return_value = {
            'Body': MagicMock(read=lambda: ics.encode())
        }
        self.customers_table.scan.return_value = {
            'Items': [{'application_id': APP_ID}]
        }
        self.members_table.query.return_value = {'Items': members}
        return self.mod.check_reminders({}, {})

    def test_sends_notification_when_event_in_window(self):
        ics = _make_ics('uid1', hours_from_now=23.5)
        self._run(ics, [_make_member(hours=24)])
        self.mod.send_push_notification.assert_called_once()

    def test_no_notification_outside_window(self):
        ics = _make_ics('uid2', hours_from_now=22.0)
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
        self.reminders_table.get_item.return_value = {
            'Item': {'applicationId': APP_ID, 'memberId_eventId': 'm1#uid5'}
        }
        self._run(ics, [_make_member(hours=24)])
        self.mod.send_push_notification.assert_not_called()

    def test_writes_dedup_entry_after_sending(self):
        ics = _make_ics('uid6', hours_from_now=23.5)
        self._run(ics, [_make_member(hours=24)])
        self.reminders_table.put_item.assert_called_once()
        item = self.reminders_table.put_item.call_args.kwargs['Item']
        self.assertEqual(item['applicationId'], APP_ID)
        self.assertEqual(item['memberId_eventId'], 'm1#uid6')
        self.assertEqual(item['memberId'], 'm1')
        self.assertEqual(item['eventId'], 'uid6')
        self.assertIn('ttl', item)

    def test_returns_200(self):
        ics = _make_ics('uid7', hours_from_now=23.5)
        result = self._run(ics, [_make_member(hours=24)])
        self.assertEqual(result['statusCode'], 200)

    def test_fcm_failure_does_not_abort_other_members(self):
        ics = _make_ics('uid8', hours_from_now=23.5)
        member1 = {**_make_member(hours=24), 'memberId': 'm1', 'token': 'tok1'}
        member2 = {**_make_member(hours=24), 'memberId': 'm2', 'token': 'tok2'}
        self.mod.send_push_notification.side_effect = [Exception('FCM error'), None]
        self.mod.s3_client.get_object.return_value = {
            'Body': MagicMock(read=lambda: ics.encode())
        }
        self.customers_table.scan.return_value = {
            'Items': [{'application_id': APP_ID}]
        }
        self.members_table.query.return_value = {'Items': [member1, member2]}
        result = self.mod.check_reminders({}, {})
        self.assertEqual(self.mod.send_push_notification.call_count, 2)
        self.assertEqual(result['statusCode'], 200)
