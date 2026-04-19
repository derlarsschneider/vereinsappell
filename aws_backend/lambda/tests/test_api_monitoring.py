import json
import sys
import unittest
from unittest.mock import MagicMock

if 'boto3' not in sys.modules:
    sys.modules['boto3'] = MagicMock()
_boto3_mock = sys.modules['boto3']

sys.path.insert(0, '.')
import api_monitoring


def _make_result(rows):
    return {
        'status': 'Complete',
        'results': [
            [{'field': k, 'value': v} for k, v in row.items()]
            for row in rows
        ],
    }


def _event(timeframe='day'):
    return {'queryStringParameters': {'timeframe': timeframe}}


def _context():
    ctx = MagicMock()
    ctx.log_group_name = '/aws/lambda/test'
    return ctx


class TestHandleMonitoringNewFields(unittest.TestCase):
    def setUp(self):
        self.mock_logs = MagicMock()
        self.mock_logs.start_query.return_value = {'queryId': 'q1'}
        _boto3_mock.client.return_value = self.mock_logs

    def test_calls_per_endpoint_aggregated_by_app_and_path(self):
        rows = [
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'},
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/fines'},
            {'applicationId': 'TZG', 'memberId': 'm2', 'path': '/members'},
            {'applicationId': 'BSV', 'memberId': 'm3', 'path': '/members'},
        ]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])

        self.assertIn('calls_per_endpoint', body)
        by_key = {(e['applicationId'], e['path']): e['count'] for e in body['calls_per_endpoint']}
        self.assertEqual(by_key[('TZG', '/members')], 2)
        self.assertEqual(by_key[('TZG', '/fines')], 1)
        self.assertEqual(by_key[('BSV', '/members')], 1)

    def test_calls_per_member_aggregated_by_app_and_member(self):
        rows = [
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'},
            {'applicationId': 'TZG', 'memberId': 'm1', 'path': '/fines'},
            {'applicationId': 'BSV', 'memberId': 'm2', 'path': '/members'},
        ]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        body = json.loads(response['body'])

        self.assertIn('calls_per_member', body)
        by_key = {(e['applicationId'], e['memberId']): e['count'] for e in body['calls_per_member']}
        self.assertEqual(by_key[('TZG', 'm1')], 2)
        self.assertEqual(by_key[('BSV', 'm2')], 1)

    def test_existing_fields_still_present(self):
        rows = [{'applicationId': 'TZG', 'memberId': 'm1', 'path': '/members'}]
        self.mock_logs.get_query_results.return_value = _make_result(rows)

        response = api_monitoring.handle_monitoring(_event(), _context())
        body = json.loads(response['body'])

        self.assertIn('calls_per_club', body)
        self.assertIn('active_members', body)
        self.assertIn('timeframe', body)
