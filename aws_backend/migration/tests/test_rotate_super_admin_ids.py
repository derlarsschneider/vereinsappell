import os
import sys
import unittest
from decimal import Decimal
from unittest.mock import MagicMock
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import rotate_super_admin_ids as rot

OLD = {
    'applicationId': 'app-1',
    'memberId': 'old-id',
    'name': 'Lars (Club)',
    'isSuperAdmin': True,
    'isAdmin': True,
    'reminderHoursBefore': Decimal('24'),
}


class TestBuildRotatedItem(unittest.TestCase):
    def test_only_member_id_changes(self):
        new = rot.build_rotated_item(OLD, 'new-id')
        self.assertEqual(new['memberId'], 'new-id')
        self.assertEqual({k: v for k, v in new.items() if k != 'memberId'},
                         {k: v for k, v in OLD.items() if k != 'memberId'})

    def test_original_is_not_mutated(self):
        rot.build_rotated_item(OLD, 'new-id')
        self.assertEqual(OLD['memberId'], 'old-id')


class TestInviteLink(unittest.TestCase):
    def test_link_contains_both_ids(self):
        link = rot.invite_link('app 1', 'id&x')
        parsed = urlparse(link)
        self.assertEqual(f'{parsed.scheme}://{parsed.netloc}', 'https://vereinsappell.web.app')
        self.assertEqual(parse_qs(parsed.query), {'applicationId': ['app 1'], 'memberId': ['id&x']})


class TestRotationTransaction(unittest.TestCase):
    def setUp(self):
        self.tx = rot.rotation_transaction('t-members', OLD, rot.build_rotated_item(OLD, 'new-id'))

    def test_put_new_then_delete_old(self):
        self.assertEqual([list(op)[0] for op in self.tx], ['Put', 'Delete'])

    def test_put_has_new_id_and_guard(self):
        put = self.tx[0]['Put']
        self.assertEqual(put['TableName'], 't-members')
        self.assertEqual(put['Item']['memberId'], {'S': 'new-id'})
        self.assertEqual(put['Item']['isSuperAdmin'], {'BOOL': True})
        self.assertEqual(put['Item']['reminderHoursBefore'], {'N': '24'})
        self.assertEqual(put['ConditionExpression'], 'attribute_not_exists(memberId)')

    def test_delete_targets_old_key_with_guard(self):
        delete = self.tx[1]['Delete']
        self.assertEqual(delete['Key'], {'applicationId': {'S': 'app-1'}, 'memberId': {'S': 'old-id'}})
        self.assertEqual(delete['ConditionExpression'], 'attribute_exists(memberId)')


class TestFindSuperAdmins(unittest.TestCase):
    def test_filters_by_application_id_and_paginates(self):
        table = MagicMock()
        table.scan.side_effect = [
            {'Items': [{'applicationId': 'b', 'memberId': '2'}], 'LastEvaluatedKey': {'x': 1}},
            {'Items': [{'applicationId': 'a', 'memberId': '1'}]},
        ]
        self.assertEqual(rot.find_super_admins(table, 'a'), [{'applicationId': 'a', 'memberId': '1'}])
        self.assertEqual(table.scan.call_count, 2)


class TestCountFines(unittest.TestCase):
    def test_counts_only_rotated_keys(self):
        table = MagicMock()
        table.scan.return_value = {'Items': [
            {'applicationId': 'app-1', 'memberId': 'old-id'},
            {'applicationId': 'app-1', 'memberId': 'old-id'},
            {'applicationId': 'app-2', 'memberId': 'old-id'},
        ]}
        self.assertEqual(rot.count_fines(table, [OLD]), {('app-1', 'old-id'): 2})


if __name__ == '__main__':
    unittest.main()
