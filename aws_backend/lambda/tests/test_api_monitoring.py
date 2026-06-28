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

        mock_table = MagicMock()
        mock_table.scan.return_value = {'Items': []}
        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table
        _boto3_mock.resource.return_value = mock_dynamodb

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


class TestHandleErrors(unittest.TestCase):
    def setUp(self):
        mock_table = MagicMock()
        mock_table.scan.return_value = {
            'Items': [
                {'id': '1', 'time': '2026-06-28T10:00:00', 'error': 'boom', 'stacktrace': 'Traceback...', 'route_key': 'GET /customers/{id}', 'headers': {'auth': 'secret'}, 'body': {'password': 'pw'}},
                {'id': '2', 'time': '2026-06-28T09:00:00', 'error': 'oops', 'stacktrace': 'Traceback2...', 'route_key': 'GET /members', 'headers': {}, 'body': {}},
            ]
        }
        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table
        _boto3_mock.resource.return_value = mock_dynamodb

    def test_returns_errors_sorted_by_time_descending(self):
        event = {'queryStringParameters': None}
        response = api_monitoring.handle_errors(event, _context())
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertIn('errors', body)
        times = [e['time'] for e in body['errors']]
        self.assertEqual(times, sorted(times, reverse=True))

    def test_strips_sensitive_fields(self):
        event = {'queryStringParameters': None}
        response = api_monitoring.handle_errors(event, _context())
        body = json.loads(response['body'])
        for entry in body['errors']:
            self.assertNotIn('headers', entry)
            self.assertNotIn('body', entry)

    def test_includes_required_fields(self):
        event = {'queryStringParameters': None}
        response = api_monitoring.handle_errors(event, _context())
        body = json.loads(response['body'])
        entry = body['errors'][0]
        for field in ('id', 'time', 'error', 'stacktrace', 'route_key'):
            self.assertIn(field, entry)

    def test_limits_to_50_entries(self):
        mock_table = MagicMock()
        mock_table.scan.return_value = {
            'Items': [{'id': str(i), 'time': f'2026-06-28T{i:02d}:00:00', 'error': 'e', 'stacktrace': 's', 'route_key': 'r'} for i in range(60)]
        }
        mock_dynamodb = MagicMock()
        mock_dynamodb.Table.return_value = mock_table
        _boto3_mock.resource.return_value = mock_dynamodb

        response = api_monitoring.handle_errors({}, _context())
        body = json.loads(response['body'])
        self.assertLessEqual(len(body['errors']), 50)
