import decimal
import json
import sys
import unittest
from unittest.mock import MagicMock, patch, call

sys.modules.setdefault('boto3', MagicMock())
sys.modules.setdefault('firebase_backup', MagicMock())

sys.path.insert(0, 'aws_backend/lambda/backup')
import backup_handler


def _api_event(method, path):
    return {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': 'app1', 'memberid': 'member1'},
    }


def _scheduler_event():
    return {'source': 'aws.events'}


class TestSuperadminCheck(unittest.TestCase):
    def setUp(self):
        backup_handler.dynamodb = MagicMock()
        backup_handler.s3 = MagicMock()
        backup_handler.MEMBERS_TABLE_NAME = 'members-table'

    def test_returns_403_when_not_superadmin(self):
        mock_table = MagicMock()
        mock_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        backup_handler.dynamodb.Table.return_value = mock_table

        response = backup_handler.lambda_handler(_api_event('POST', '/admin/backup'), {})

        self.assertEqual(response['statusCode'], 403)

    def test_returns_403_when_member_not_found(self):
        mock_table = MagicMock()
        mock_table.get_item.return_value = {}
        backup_handler.dynamodb.Table.return_value = mock_table

        response = backup_handler.lambda_handler(_api_event('POST', '/admin/backup'), {})

        self.assertEqual(response['statusCode'], 403)


class TestBackupRun(unittest.TestCase):
    def setUp(self):
        backup_handler.dynamodb = MagicMock()
        backup_handler.s3 = MagicMock()
        backup_handler.MEMBERS_TABLE_NAME = 'members-table'
        backup_handler.TABLES = {
            'members': 'vereins-app-beta-members',
            'fines': 'vereins-app-beta-fines',
        }
        backup_handler.BACKUP_BUCKET = 'vereinsappell-backups'

        mock_member_table = MagicMock()
        mock_member_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}

        mock_data_table = MagicMock()
        mock_data_table.scan.return_value = {'Items': [{'id': '1'}]}

        def table_factory(name):
            if name == 'members-table':
                return mock_member_table
            return mock_data_table

        backup_handler.dynamodb.Table.side_effect = table_factory

    def test_scheduler_trigger_skips_superadmin_check(self):
        response = backup_handler.lambda_handler(_scheduler_event(), {})
        self.assertEqual(response['statusCode'], 200)

    def test_backup_writes_json_to_s3_for_each_table(self):
        backup_handler.lambda_handler(_scheduler_event(), {})
        self.assertEqual(backup_handler.s3.put_object.call_count, 2)

    def test_backup_returns_s3_path_and_timestamp(self):
        response = backup_handler.lambda_handler(_scheduler_event(), {})
        body = json.loads(response['body'])
        self.assertIn('s3_path', body)
        self.assertIn('timestamp', body)
        self.assertEqual(body['failed'], [])

    def test_partial_backup_on_table_failure(self):
        backup_handler.s3.put_object.side_effect = [Exception('S3 error'), None]
        response = backup_handler.lambda_handler(_scheduler_event(), {})
        body = json.loads(response['body'])
        self.assertEqual(len(body['failed']), 1)
        self.assertIn('-partial', body['s3_path'])

    def test_api_trigger_with_superadmin_runs_backup(self):
        response = backup_handler.lambda_handler(
            _api_event('POST', '/admin/backup'), {}
        )
        self.assertEqual(response['statusCode'], 200)

    def test_decimal_values_serialized_as_numbers_not_strings(self):
        mock_member_table = MagicMock()
        mock_member_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        mock_data_table = MagicMock()
        mock_data_table.scan.return_value = {
            'Items': [{'fineId': 'abc', 'amount': decimal.Decimal('5'), 'rate': decimal.Decimal('1.5')}]
        }
        backup_handler.dynamodb.Table.side_effect = lambda name: (
            mock_member_table if name == 'members-table' else mock_data_table
        )

        backup_handler.lambda_handler(_scheduler_event(), {})

        call_body = backup_handler.s3.put_object.call_args_list[0][1]['Body']
        items = json.loads(call_body)
        self.assertEqual(items[0]['amount'], 5)
        self.assertEqual(items[0]['rate'], 1.5)


class TestListBackups(unittest.TestCase):
    def setUp(self):
        backup_handler.dynamodb = MagicMock()
        backup_handler.s3 = MagicMock()
        backup_handler.MEMBERS_TABLE_NAME = 'members-table'
        backup_handler.BACKUP_BUCKET = 'vereinsappell-backups'

        mock_table = MagicMock()
        mock_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        backup_handler.dynamodb.Table.return_value = mock_table

    def test_returns_sorted_backup_list(self):
        backup_handler.s3.list_objects_v2.return_value = {
            'CommonPrefixes': [
                {'Prefix': 'dynamodb/2026-05-10_02-00/'},
                {'Prefix': 'dynamodb/2026-05-11_02-00/'},
            ]
        }
        response = backup_handler.lambda_handler(
            _api_event('GET', '/admin/backups'), {}
        )
        body = json.loads(response['body'])
        self.assertEqual(body['backups'][0], '2026-05-11_02-00')
        self.assertEqual(body['backups'][1], '2026-05-10_02-00')
