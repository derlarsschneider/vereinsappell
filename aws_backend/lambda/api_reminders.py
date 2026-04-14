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

    # Unfold RFC 5545 continuation lines (CRLF or LF + whitespace)
    unfolded = re.sub(r'\r?\n[ \t]', '', ics_content)

    for raw_line in unfolded.split('\n'):
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
