import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import authorizer

HEADERS = {'applicationid': 'app-123', 'memberid': 'member-1'}


def _call(member, headers=HEADERS):
    with patch.object(authorizer, '_get_member', return_value=member) as get_member:
        result = authorizer.lambda_authorizer({'headers': headers}, None)
    return result, get_member


class TestAuthorizer(unittest.TestCase):

    def test_unknown_member_denied(self):
        result, _ = _call(None)
        self.assertIs(result['isAuthorized'], False)

    def test_missing_headers_denied(self):
        result, get_member = _call({'isActive': True}, headers={})
        self.assertIs(result['isAuthorized'], False)
        get_member.assert_not_called()

    def test_active_member_allowed(self):
        result, get_member = _call({'isActive': True})
        self.assertIs(result['isAuthorized'], True)
        get_member.assert_called_once_with('app-123', 'member-1')

    def test_member_without_isActive_allowed(self):
        result, _ = _call({})
        self.assertIs(result['isAuthorized'], True)

    def test_inactive_member_denied(self):
        result, _ = _call({'isActive': False})
        self.assertIs(result['isAuthorized'], False)

    def test_inactive_super_admin_allowed(self):
        result, _ = _call({'isActive': False, 'isSuperAdmin': True})
        self.assertIs(result['isAuthorized'], True)

    def test_eventbridge_allowed(self):
        with patch.object(authorizer, '_get_member') as get_member:
            result = authorizer.lambda_authorizer({'source': 'aws.events'}, None)
        self.assertIs(result['isAuthorized'], True)
        get_member.assert_not_called()


if __name__ == '__main__':
    unittest.main()


class TestGetMember(unittest.TestCase):
    def test_uses_module_level_table_without_creating_a_new_resource(self):
        table = MagicMock()
        table.get_item.return_value = {'Item': {'memberId': 'm'}}
        with patch.object(authorizer, '_members_table', table), \
             patch.object(authorizer.boto3, 'resource') as resource:
            self.assertEqual(authorizer._get_member('a', 'm'), {'memberId': 'm'})
        table.get_item.assert_called_once_with(Key={'applicationId': 'a', 'memberId': 'm'})
        resource.assert_not_called()
