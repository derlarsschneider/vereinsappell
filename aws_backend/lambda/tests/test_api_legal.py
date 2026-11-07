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
        self.assertEqual(self.mock_table.update_item.call_count, 2)

    def test_put_legal_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {
            'Item': {'isSuperAdmin': False}
        }
        event = _event('PUT', '/legal', member_id='user1', body={
            'datenschutz': 'x', 'impressum': 'y',
        })
        response = api_legal.put_legal(event)
        self.assertEqual(response['statusCode'], 403)
        self.mock_table.update_item.assert_not_called()


class TestHandleLegal(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_legal.legal_texts_table = self.mock_table
        api_legal.members_table = self.mock_members_table

    def test_get_delegates_to_get_legal(self):
        self.mock_table.get_item.side_effect = [
            {'Item': {'id': 'datenschutz', 'text': 'DS'}},
            {'Item': {'id': 'impressum', 'text': 'IMP'}},
        ]
        event = _event('GET', '/legal')
        response = api_legal.handle_legal(event, {})
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertIn('datenschutz', body)
        self.assertIn('impressum', body)

    def test_put_as_non_superadmin_returns_403(self):
        self.mock_members_table.get_item.return_value = {
            'Item': {'isSuperAdmin': False}
        }
        event = _event('PUT', '/legal', member_id='user1', body={
            'datenschutz': 'x', 'impressum': 'y',
        })
        response = api_legal.handle_legal(event, {})
        self.assertEqual(response['statusCode'], 403)

    def test_unknown_method_returns_404(self):
        event = _event('DELETE', '/legal')
        response = api_legal.handle_legal(event, {})
        self.assertEqual(response['statusCode'], 404)


if __name__ == '__main__':
    unittest.main()
