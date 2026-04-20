import decimal
import json
import re
from datetime import timedelta


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, decimal.Decimal):
            return str(o)
        return super().default(o)


def parse_timeframe(timeframe_str, default_days=1):
    """
    Parses timeframe strings like '15minutes', '1 hour', '2days', 'week'
    and returns a timedelta object.
    """
    if not timeframe_str:
        return timedelta(days=default_days)

    # Handle simple predefined keywords
    keywords = {
        'minute': timedelta(minutes=1),
        'hour': timedelta(hours=1),
        'day': timedelta(days=1),
        'week': timedelta(weeks=1),
        'month': timedelta(days=30),
        'year': timedelta(days=365),
    }
    if timeframe_str in keywords:
        return keywords[timeframe_str]

    # Use regex to find number and unit (e.g., "15minutes" or "2 days")
    match = re.match(r'(\d+)\s*([a-zA-Z]+)', timeframe_str)
    if not match:
        # Fallback to predefined keywords if part of a string (like 'minutes' instead of 'minute')
        for k, v in keywords.items():
            if k in timeframe_str.lower():
                return v
        return timedelta(days=default_days)

    value = int(match.group(1))
    unit = match.group(2).lower()

    if unit.startswith('minute'):
        return timedelta(minutes=value)
    elif unit.startswith('hour'):
        return timedelta(hours=value)
    elif unit.startswith('day'):
        return timedelta(days=value)
    elif unit.startswith('week'):
        return timedelta(weeks=value)
    elif unit.startswith('month'):
        return timedelta(days=value * 30)
    elif unit.startswith('year'):
        return timedelta(days=value * 365)

    return timedelta(days=default_days)
