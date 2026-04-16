import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_customers


def _event(method, path, body=None, customer_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {},
        'pathParameters': {},
    }
    if customer_id:
        event['pathParameters']['customerId'] = customer_id
    if body is not None:
        event['body'] = json.dumps(body)
    return event


class TestListCustomers(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_returns_all_clubs(self):
        clubs = [
            {'application_id': 'club1', 'application_name': 'Club 1'},
            {'application_id': 'club2', 'application_name': 'Club 2'},
        ]
        self.mock_table.scan.return_value = {'Items': clubs}
        response = api_customers.list_customers()
        self.assertEqual(response['statusCode'], 200)
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]['application_id'], 'club1')

    def test_handles_pagination(self):
        self.mock_table.scan.side_effect = [
            {'Items': [{'application_id': 'c1'}], 'LastEvaluatedKey': {'application_id': 'c1'}},
            {'Items': [{'application_id': 'c2'}]},
        ]
        response = api_customers.list_customers()
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)


class TestUpdateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_update_customer(self):
        event = _event(
            'PUT', '/customers/club1',
            body={'application_name': 'New Name', 'active_screens': ['termine', 'strafen']},
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.update_item.assert_called_once()
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertEqual(call_kwargs['Key'], {'application_id': 'club1'})

    def test_update_customer_with_logo(self):
        event = _event(
            'PUT', '/customers/club1',
            body={
                'application_name': 'New Name',
                'application_logo': 'abc123',
                'active_screens': ['termine'],
            },
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertIn(':logo', call_kwargs['ExpressionAttributeValues'])


class TestCreateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_create_customer_success(self):
        event = _event(
            'POST', '/customers',
            body={'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = json.loads(response['body'])
        # application_id is a server-generated UUID
        self.assertIn('application_id', item)
        self.assertEqual(len(item['application_id']), 36)  # UUID format

    def test_create_customer_defaults_active_screens(self):
        event = _event(
            'POST', '/customers',
            body={'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(len(item['active_screens']), len(api_customers.ALL_SCREEN_KEYS))

    def test_create_customer_uses_api_base_url_default(self):
        with patch.object(api_customers, 'API_BASE_URL', 'https://api.example.com'):
            event = _event(
                'POST', '/customers',
                body={'application_name': 'New Club'},
            )
            response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(item['api_url'], 'https://api.example.com')

    def test_create_customer_response_includes_member_id(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        event['headers'] = {'memberid': 'super123'}
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['member_id'], 'super123')

    def test_create_customer_response_includes_api_base_url(self):
        with patch.object(api_customers, 'API_BASE_URL', 'https://api.example.com'):
            event = _event('POST', '/customers', body={'application_name': 'New Club'})
            event['headers'] = {}
            response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['api_base_url'], 'https://api.example.com')

    def test_create_customer_response_member_id_empty_when_no_header(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        # no 'headers' key — must not crash
        event.pop('headers', None)
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['member_id'], '')
