import decimal
import json
import sys
import unittest
from unittest.mock import MagicMock, patch

# Pre-patch modules imported at lambda_handler load time
_boto3_mock = MagicMock()
_conditions_mock = MagicMock()
_conditions_mock.Key = MagicMock(return_value=MagicMock())
sys.modules.setdefault('boto3', _boto3_mock)
sys.modules.setdefault('boto3.dynamodb', MagicMock())
sys.modules.setdefault('boto3.dynamodb.conditions', _conditions_mock)
sys.modules['push_notifications'] = MagicMock()
sys.modules['error_handler'] = MagicMock()
sys.modules['api_members'] = MagicMock()
sys.modules['api_docs'] = MagicMock()

sys.path.insert(0, '.')
import lambda_handler


def _fines_event(method, path, params=None, body=None, path_params=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {},
        'queryStringParameters': params or {},
        'pathParameters': path_params or {},
    }
    if body:
        event['body'] = json.dumps(body)
    return event


class TestGetFines(unittest.TestCase):
    def setUp(self):
        self.mock_members = MagicMock()
        self.mock_fines = MagicMock()
        lambda_handler.members_table = self.mock_members
        lambda_handler.fines_table = self.mock_fines

    def test_get_fines_without_member_id_returns_400(self):
        event = _fines_event('GET', '/fines')
        response = lambda_handler.get_fines(event)
        self.assertEqual(response['statusCode'], 400)

    def test_get_fines_returns_name_and_fines(self):
        self.mock_members.query.return_value = {
            'Items': [{'memberId': 'user1', 'name': 'Max Muster'}]
        }
        self.mock_fines.query.return_value = {
            'Items': [{'fineId': 'f1', 'reason': 'Zu spät', 'amount': '5'}]
        }
        event = _fines_event('GET', '/fines', params={'memberId': 'user1'})
        response = lambda_handler.get_fines(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['name'], 'Max Muster')
        self.assertIn('fines', body)

    def test_get_fines_serializes_decimal_as_string(self):
        self.mock_members.query.return_value = {
            'Items': [{'memberId': 'user1', 'name': 'Max'}]
        }
        self.mock_fines.query.return_value = {
            'Items': [{'fineId': 'f1', 'reason': 'Test', 'amount': decimal.Decimal('10.50')}]
        }
        event = _fines_event('GET', '/fines', params={'memberId': 'user1'})
        response = lambda_handler.get_fines(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['fines'][0]['amount'], '10.50')


class TestAddFine(unittest.TestCase):
    def setUp(self):
        self.mock_members = MagicMock()
        self.mock_fines = MagicMock()
        lambda_handler.members_table = self.mock_members
        lambda_handler.fines_table = self.mock_fines
        self.mock_members.get_item.return_value = {
            'Item': {'memberId': 'user1', 'name': 'Max', 'token': None}
        }
        self.mock_fines.put_item.return_value = {}

    def test_add_fine_generates_uuid_as_fine_id(self):
        body = {'memberId': 'user1', 'reason': 'Test', 'amount': '5'}
        event = _fines_event('POST', '/fines', body=body)
        response = lambda_handler.add_fine(event)
        self.assertEqual(response['statusCode'], 200)
        put_call = self.mock_fines.put_item.call_args
        item = put_call.kwargs['Item']
        self.assertIn('fineId', item)
        self.assertEqual(len(item['fineId']), 36)  # UUID length

    def test_add_fine_stores_all_fields(self):
        body = {'memberId': 'user1', 'reason': 'Zu spät', 'amount': '10'}
        event = _fines_event('POST', '/fines', body=body)
        response = lambda_handler.add_fine(event)
        self.assertEqual(response['statusCode'], 200)
        put_call = self.mock_fines.put_item.call_args
        item = put_call.kwargs['Item']
        self.assertEqual(item['memberId'], 'user1')
        self.assertEqual(item['reason'], 'Zu spät')
        self.assertEqual(item['amount'], '10')


class TestDeleteFine(unittest.TestCase):
    def setUp(self):
        self.mock_fines = MagicMock()
        lambda_handler.fines_table = self.mock_fines
        self.mock_fines.delete_item.return_value = {}

    def test_delete_fine_calls_delete_item_with_composite_key(self):
        event = _fines_event(
            'DELETE', '/fines/f1',
            params={'memberId': 'user1'},
            path_params={'fineId': 'f1'},
        )
        response = lambda_handler.delete_fine(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_fines.delete_item.assert_called_once_with(
            Key={'memberId': 'user1', 'fineId': 'f1'}
        )


if __name__ == '__main__':
    unittest.main()
