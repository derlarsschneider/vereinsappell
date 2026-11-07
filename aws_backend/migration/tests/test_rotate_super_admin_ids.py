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


class TestRotationTransactionWithFines(unittest.TestCase):
    def setUp(self):
        self.tx = rot.rotation_transaction(
            't-members', OLD, rot.build_rotated_item(OLD, 'new-id'), 't-fines', ['f1', 'f2'])

    def test_member_ops_then_one_update_per_fine(self):
        self.assertEqual([list(op)[0] for op in self.tx], ['Put', 'Delete', 'Update', 'Update'])

    def test_fine_update_moves_member_id_with_guard(self):
        update = self.tx[2]['Update']
        self.assertEqual(update['TableName'], 't-fines')
        self.assertEqual(update['Key'], {'applicationId': {'S': 'app-1'}, 'fineId': {'S': 'f1'}})
        self.assertEqual(update['UpdateExpression'], 'SET memberId = :new')
        self.assertEqual(update['ConditionExpression'], 'memberId = :old')
        self.assertEqual(update['ExpressionAttributeValues'],
                         {':new': {'S': 'new-id'}, ':old': {'S': 'old-id'}})
        self.assertEqual(self.tx[3]['Update']['Key']['fineId'], {'S': 'f2'})

    def test_too_many_fines_for_one_transaction_raises(self):
        with self.assertRaises(ValueError):
            rot.rotation_transaction('t-members', OLD, rot.build_rotated_item(OLD, 'new-id'),
                                     't-fines', [f'f{i}' for i in range(99)])

    def test_98_fines_fit(self):
        tx = rot.rotation_transaction('t-members', OLD, rot.build_rotated_item(OLD, 'new-id'),
                                      't-fines', [f'f{i}' for i in range(98)])
        self.assertEqual(len(tx), 100)


class TestFinesByMember(unittest.TestCase):
    def test_collects_fine_ids_only_for_rotated_keys(self):
        table = MagicMock()
        table.scan.return_value = {'Items': [
            {'applicationId': 'app-1', 'memberId': 'old-id', 'fineId': 'f1'},
            {'applicationId': 'app-1', 'memberId': 'old-id', 'fineId': 'f2'},
            {'applicationId': 'app-2', 'memberId': 'old-id', 'fineId': 'f3'},
            {'applicationId': 'app-1', 'memberId': 'other', 'fineId': 'f4'},
        ]}
        self.assertEqual(rot.fines_by_member(table, [OLD]), {('app-1', 'old-id'): ['f1', 'f2']})
        self.assertIn('fineId', table.scan.call_args.kwargs['ProjectionExpression'])


class TestDefaultAdminName(unittest.TestCase):
    def test_first_name_and_club(self):
        self.assertEqual(rot.default_admin_name('Lars Schiller', 'Neuss'), 'Lars (Neuss)')

    def test_empty_name_falls_back(self):
        self.assertEqual(rot.default_admin_name('', 'Neuss'), 'Admin (Neuss)')


class TestSplitTransaction(unittest.TestCase):
    def setUp(self):
        admin = rot.build_split_admin_item('app-1', 'admin-id', 'Lars (Club)')
        self.tx = rot.split_transaction('t-members', OLD, admin)

    def test_put_admin_then_update_personal(self):
        self.assertEqual([list(op)[0] for op in self.tx], ['Put', 'Update'])

    def test_admin_row_is_super_admin_with_new_id(self):
        put = self.tx[0]['Put']
        self.assertEqual(put['Item']['memberId'], {'S': 'admin-id'})
        self.assertEqual(put['Item']['applicationId'], {'S': 'app-1'})
        self.assertEqual(put['Item']['isSuperAdmin'], {'BOOL': True})
        self.assertEqual(put['Item']['isAdmin'], {'BOOL': True})
        self.assertEqual(put['Item']['isActive'], {'BOOL': True})
        self.assertNotIn('token', put['Item'])
        self.assertEqual(put['ConditionExpression'], 'attribute_not_exists(memberId)')

    def test_personal_row_only_loses_super_admin(self):
        update = self.tx[1]['Update']
        self.assertEqual(update['Key'], {'applicationId': {'S': 'app-1'}, 'memberId': {'S': 'old-id'}})
        self.assertEqual(update['UpdateExpression'], 'SET isSuperAdmin = :false')
        self.assertEqual(update['ConditionExpression'], 'isSuperAdmin = :true')
        self.assertEqual(update['ExpressionAttributeValues'],
                         {':false': {'BOOL': False}, ':true': {'BOOL': True}})


if __name__ == '__main__':
    unittest.main()
