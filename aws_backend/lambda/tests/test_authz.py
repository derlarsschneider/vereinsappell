import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())
os.environ.setdefault('MEMBERS_TABLE_NAME', 'members-test')

sys.path.insert(0, '.')
import authz
from authz import Caller

APP_ID = 'app-123'


def _event(headers):
    return {'headers': headers}


class TestGetCaller(unittest.TestCase):
    def test_get_caller_reads_flags(self):
        table = MagicMock()
        table.get_item.return_value = {'Item': {'isAdmin': True, 'isSpiess': False, 'isSuperAdmin': True}}
        with patch.object(authz, 'members_table', table):
            caller = authz.get_caller(_event({'applicationid': APP_ID, 'memberid': 'm1'}))
        self.assertEqual(caller, Caller(APP_ID, 'm1', True, False, True))
        table.get_item.assert_called_once_with(Key={'applicationId': APP_ID, 'memberId': 'm1'})

    def test_get_caller_unknown_member_has_no_roles(self):
        table = MagicMock()
        table.get_item.return_value = {}
        with patch.object(authz, 'members_table', table):
            caller = authz.get_caller(_event({'applicationid': APP_ID, 'memberid': 'ghost'}))
        self.assertEqual(caller, Caller(APP_ID, 'ghost', False, False, False))

    def test_get_caller_missing_memberid_does_not_query(self):
        table = MagicMock()
        with patch.object(authz, 'members_table', table):
            caller = authz.get_caller(_event({'applicationid': APP_ID}))
        self.assertEqual(caller, Caller(APP_ID, '', False, False, False))
        table.get_item.assert_not_called()

    def test_get_caller_none_headers(self):
        table = MagicMock()
        with patch.object(authz, 'members_table', table):
            caller = authz.get_caller({'headers': None})
        self.assertFalse(caller.is_admin)
        table.get_item.assert_not_called()


class TestForbidden(unittest.TestCase):
    def test_forbidden_shape(self):
        resp = authz.forbidden({'Access-Control-Allow-Origin': '*'})
        self.assertEqual(resp['statusCode'], 403)
        self.assertEqual(json.loads(resp['body']), {'error': 'Nicht berechtigt'})
        self.assertEqual(resp['Access-Control-Allow-Origin'], '*')

    def test_forbidden_statuscode_and_body_win(self):
        resp = authz.forbidden({'statusCode': 200, 'body': 'x'})
        self.assertEqual(resp['statusCode'], 403)
        self.assertEqual(json.loads(resp['body']), {'error': 'Nicht berechtigt'})


class TestCanManageClub(unittest.TestCase):
    def test_can_manage_club(self):
        admin = Caller(APP_ID, 'm', True, False, False)
        self.assertTrue(admin.can_manage_club(APP_ID))
        self.assertFalse(admin.can_manage_club('other'))
        self.assertTrue(Caller(APP_ID, 'm', False, False, True).can_manage_club('other'))
        self.assertFalse(Caller(APP_ID, 'm', False, False, False).can_manage_club(APP_ID))


if __name__ == '__main__':
    unittest.main()
