import json
import sys
import unittest
from unittest.mock import MagicMock, patch

# Pre-patch modules that api_members imports at module level
sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_members


def _event(method, path, headers=None, member_id=None, body=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': headers or {},
        'pathParameters': {},
    }
    if member_id:
        event['pathParameters']['memberId'] = member_id
    if body:
        event['body'] = json.dumps(body)
    return event


def _admin_event(method, path, **kwargs):
    return _event(method, path, headers={'memberid': 'admin1'}, **kwargs)


class TestListMembers(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_members.members_table = self.mock_table

        self.admin = {'memberId': 'admin1', 'isAdmin': True, 'isSpiess': False}
        self.member = {'memberId': 'user1', 'isAdmin': False, 'isSpiess': False}

        def get_item_side_effect(Key):
            data = {'admin1': self.admin, 'user1': self.member}
            item = data.get(Key.get('memberId'))
            return {'Item': item} if item else {}

        self.mock_table.get_item.side_effect = get_item_side_effect
        self.mock_table.scan.return_value = {'Items': [self.admin, self.member]}

    def test_list_members_as_admin(self):
        event = _admin_event('GET', '/members')
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)

    def test_list_members_as_non_admin(self):
        event = _event('GET', '/members', headers={'memberid': 'user1'})
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 403)


class TestGetMember(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_members.members_table = self.mock_table

        self.admin = {'memberId': 'admin1', 'isAdmin': True, 'isSpiess': False}
        self.full_member = {
            'memberId': 'user1',
            'name': 'Max Mustermann',
            'isAdmin': False,
            'isSpiess': False,
            'token': 'tok',
            'street': 'Hauptstr. 1',
            'phone1': '0123',
        }

        def get_item_side_effect(Key):
            data = {'admin1': self.admin, 'user1': self.full_member}
            item = data.get(Key.get('memberId'))
            return {'Item': item} if item else {}

        self.mock_table.get_item.side_effect = get_item_side_effect

    def test_get_member_reduced_fields(self):
        event = _admin_event('GET', '/members/user1', member_id='user1')
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertNotIn('street', body)
        self.assertNotIn('phone1', body)
        self.assertIn('memberId', body)
        self.assertIn('name', body)

    def test_get_member_not_found(self):
        event = _admin_event('GET', '/members/unknown', member_id='unknown')
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 404)


class TestAddMember(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_members.members_table = self.mock_table

        self.admin = {'memberId': 'admin1', 'isAdmin': True, 'isSpiess': False}
        self.mock_table.get_item.return_value = {'Item': self.admin}
        self.mock_table.put_item.return_value = {}

    def test_add_member_defaults_is_active_true(self):
        body = {'memberId': 'new1', 'name': 'Neues Mitglied'}
        event = _admin_event('POST', '/members', body=body)
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        put_call = self.mock_table.put_item.call_args
        item = put_call.kwargs['Item']
        self.assertTrue(item['isActive'])

    def test_add_member_stores_is_active_false(self):
        body = {'memberId': 'new2', 'name': 'Inaktives Mitglied', 'isActive': False}
        event = _admin_event('POST', '/members', body=body)
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        put_call = self.mock_table.put_item.call_args
        item = put_call.kwargs['Item']
        self.assertFalse(item['isActive'])


class TestDeleteMember(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_members.members_table = self.mock_table

        self.admin = {'memberId': 'admin1', 'isAdmin': True, 'isSpiess': False}
        self.user = {'memberId': 'user1', 'isAdmin': False, 'isSpiess': False}

        def get_item_side_effect(Key):
            data = {'admin1': self.admin, 'user1': self.user}
            item = data.get(Key.get('memberId'))
            return {'Item': item} if item else {}

        self.mock_table.get_item.side_effect = get_item_side_effect
        self.mock_table.delete_item.return_value = {}

    def test_delete_member_calls_delete_item(self):
        event = _admin_event('DELETE', '/members/user1', member_id='user1')
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.delete_item.assert_called_once_with(Key={'memberId': 'user1'})

    def test_delete_member_as_non_admin(self):
        event = _event('DELETE', '/members/user1', headers={'memberid': 'user1'}, member_id='user1')
        response = api_members.handle_members(event, {})
        self.assertEqual(response['statusCode'], 403)


if __name__ == '__main__':
    unittest.main()
