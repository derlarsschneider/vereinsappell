import sys
import os
import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock

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
