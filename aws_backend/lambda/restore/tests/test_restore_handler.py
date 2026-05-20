import decimal
import json
import sys
import unittest
from unittest.mock import MagicMock, call

sys.modules.setdefault('boto3', MagicMock())
sys.modules.setdefault('firebase_backup', MagicMock())

sys.path.insert(0, 'aws_backend/lambda/restore')
import restore_handler


def _event(method, path, path_params=None):
    return {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': 'app1', 'memberid': 'member1'},
        'pathParameters': path_params or {},
    }


def _superadmin_table():
    t = MagicMock()
    t.get_item.return_value = {'Item': {'isSuperAdmin': True}}
    return t


class TestSuperadminCheck(unittest.TestCase):
    def setUp(self):
        restore_handler.dynamodb = MagicMock()
        restore_handler.s3 = MagicMock()
        restore_handler.MEMBERS_TABLE_NAME = 'members-table'

        mock_table = MagicMock()
        mock_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        restore_handler.dynamodb.Table.return_value = mock_table

    def test_returns_403_when_not_superadmin(self):
        response = restore_handler.lambda_handler(
            _event('POST', '/admin/backup/2026-05-11_02-00/restore',
                   {'timestamp': '2026-05-11_02-00'}), {}
        )
        self.assertEqual(response['statusCode'], 403)


class TestRestore(unittest.TestCase):
    def setUp(self):
        restore_handler.dynamodb = MagicMock()
        restore_handler.s3 = MagicMock()
        restore_handler.MEMBERS_TABLE_NAME = 'members-table'
        restore_handler.BACKUP_BUCKET = 'vereinsappell-backups'
        restore_handler.TABLES = {
            'members': 'vereins-app-beta-members',
            'fines': 'vereins-app-beta-fines',
        }

        member_table = _superadmin_table()
        data_table = MagicMock()
        restore_handler.dynamodb.Table.side_effect = lambda name: (
            member_table if name == 'members-table' else data_table
        )

        restore_handler.s3.list_objects_v2.return_value = {
            'Contents': [{'Key': 'dynamodb/2026-05-11_02-00/members.json'}]
        }
        restore_handler.s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: json.dumps([{'applicationId': 'a', 'memberId': 'm'}]).encode())
        }

    def test_restore_puts_items_from_backup(self):
        response = restore_handler.lambda_handler(
            _event('POST', '/admin/backup/2026-05-11_02-00/restore',
                   {'timestamp': '2026-05-11_02-00'}), {}
        )
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertIn('restored', body)

    def test_restore_decimal_numbers_preserved_as_decimal_type(self):
        restore_handler.s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: json.dumps([{
                'applicationId': 'a', 'memberId': 'm', 'fineId': 'f1',
                'amount': 5, 'rate': 1.5
            }]).encode())
        }
        restore_handler.lambda_handler(
            _event('POST', '/admin/backup/2026-05-11_02-00/restore',
                   {'timestamp': '2026-05-11_02-00'}), {}
        )
        put_calls = restore_handler.dynamodb.Table.return_value.__enter__.return_value.put_item.call_args_list
        if put_calls:
            item = put_calls[0][1]['Item']
            self.assertIsInstance(item.get('amount'), decimal.Decimal)

    def test_restore_failed_entries_include_error_message(self):
        restore_handler.s3.get_object.side_effect = Exception('NoSuchKey')
        response = restore_handler.lambda_handler(
            _event('POST', '/admin/backup/2026-05-11_02-00/restore',
                   {'timestamp': '2026-05-11_02-00'}), {}
        )
        body = json.loads(response['body'])
        self.assertTrue(all('table' in f and 'error' in f for f in body['failed']))
        self.assertIn('NoSuchKey', body['failed'][0]['error'])

    def test_restore_returns_404_when_timestamp_not_found(self):
        restore_handler.s3.list_objects_v2.return_value = {'Contents': []}
        response = restore_handler.lambda_handler(
            _event('POST', '/admin/backup/unknown/restore', {'timestamp': 'unknown'}), {}
        )
        self.assertEqual(response['statusCode'], 404)


class TestClearTable(unittest.TestCase):
    def setUp(self):
        restore_handler.dynamodb = MagicMock()
        restore_handler.s3 = MagicMock()
        restore_handler.MEMBERS_TABLE_NAME = 'members-table'
        restore_handler.TABLES = {
            'members': 'vereins-app-beta-members',
            'fines': 'vereins-app-beta-fines',
        }
        restore_handler.TABLE_KEYS = {
            'members': ['applicationId', 'memberId'],
            'fines': ['applicationId', 'fineId'],
        }

        member_table = _superadmin_table()
        data_table = MagicMock()
        data_table.scan.return_value = {
            'Items': [
                {'applicationId': 'a', 'memberId': 'm1'},
                {'applicationId': 'a', 'memberId': 'm2'},
            ]
        }
        restore_handler.dynamodb.Table.side_effect = lambda name: (
            member_table if name == 'members-table' else data_table
        )

    def test_clear_deletes_all_items(self):
        response = restore_handler.lambda_handler(
            _event('DELETE', '/admin/table/members/items', {'tableName': 'members'}), {}
        )
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['deleted'], 2)

    def test_clear_rejects_unknown_table(self):
        response = restore_handler.lambda_handler(
            _event('DELETE', '/admin/table/unknown/items', {'tableName': 'unknown'}), {}
        )
        self.assertEqual(response['statusCode'], 400)
