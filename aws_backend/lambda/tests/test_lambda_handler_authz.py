import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

os.environ.setdefault('MEMBERS_TABLE_NAME', 'members-test')
os.environ.setdefault('AWS_DEFAULT_REGION', 'eu-central-1')

_boto3_mock = MagicMock()
_conditions_mock = MagicMock()
sys.modules.setdefault('boto3', _boto3_mock)
sys.modules.setdefault('boto3.dynamodb', MagicMock())
sys.modules.setdefault('boto3.dynamodb.conditions', _conditions_mock)
sys.modules['push_notifications'] = MagicMock()
sys.modules['error_handler'] = MagicMock()
sys.modules['api_members'] = MagicMock()
sys.modules['api_docs'] = MagicMock()

sys.path.insert(0, '.')
import lambda_handler
from authz import Caller

OWN = 'club-a'
OTHER = 'club-b'


def make_event(method, path, path_params=None, body=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': OWN, 'memberid': 'm1'},
        'queryStringParameters': {},
        'pathParameters': path_params or {},
    }
    if body is not None:
        event['body'] = json.dumps(body)
    return event


def make_caller(admin=False, spiess=False, super_admin=False, application_id=OWN):
    return Caller(application_id=application_id, member_id='m1', is_admin=admin,
                  is_spiess=spiess, is_super_admin=super_admin)


class AuthzTestCase(unittest.TestCase):
    def call(self, event, caller):
        with patch.object(lambda_handler, 'get_caller', return_value=caller) as gc:
            response = lambda_handler.lambda_handler(event, None)
        self.assertLessEqual(gc.call_count, 1)
        return response

    def assertForbidden(self, response):
        self.assertEqual(response['statusCode'], 403)
        self.assertEqual(json.loads(response['body']), {'error': 'Nicht berechtigt'})


class TestCustomerRoutes(AuthzTestCase):
    def setUp(self):
        self.api = MagicMock()
        for name in ('list_customers', 'create_customer', 'get_customer_by_id', 'update_customer'):
            getattr(self.api, name).return_value = {'statusCode': 200, 'body': '{}'}
        patcher = patch.dict(sys.modules, {'api_customers': self.api})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_list_customers_super_admin_allowed(self):
        r = self.call(make_event('GET', '/customers'), make_caller(super_admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.api.list_customers.assert_called_once()

    def test_list_customers_admin_forbidden(self):
        r = self.call(make_event('GET', '/customers'), make_caller(admin=True))
        self.assertForbidden(r)
        self.api.list_customers.assert_not_called()

    def test_create_customer_super_admin_allowed(self):
        r = self.call(make_event('POST', '/customers', body={}), make_caller(super_admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.api.create_customer.assert_called_once()

    def test_create_customer_admin_forbidden(self):
        r = self.call(make_event('POST', '/customers', body={}), make_caller(admin=True))
        self.assertForbidden(r)
        self.api.create_customer.assert_not_called()

    def test_get_own_customer_allowed(self):
        r = self.call(make_event('GET', f'/customers/{OWN}', {'customerId': OWN}), make_caller())
        self.assertEqual(r['statusCode'], 200)
        self.api.get_customer_by_id.assert_called_once()

    def test_get_other_customer_forbidden(self):
        r = self.call(make_event('GET', f'/customers/{OTHER}', {'customerId': OTHER}),
                      make_caller(admin=True))
        self.assertForbidden(r)
        self.api.get_customer_by_id.assert_not_called()

    def test_get_other_customer_as_super_admin_allowed(self):
        r = self.call(make_event('GET', f'/customers/{OTHER}', {'customerId': OTHER}),
                      make_caller(super_admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.api.get_customer_by_id.assert_called_once()

    def test_put_own_club_as_admin_allowed(self):
        r = self.call(make_event('PUT', f'/customers/{OWN}', {'customerId': OWN}, {}),
                      make_caller(admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.api.update_customer.assert_called_once()

    def test_put_own_club_as_non_admin_forbidden(self):
        r = self.call(make_event('PUT', f'/customers/{OWN}', {'customerId': OWN}, {}),
                      make_caller())
        self.assertForbidden(r)
        self.api.update_customer.assert_not_called()

    def test_put_other_club_as_admin_forbidden(self):
        r = self.call(make_event('PUT', f'/customers/{OTHER}', {'customerId': OTHER}, {}),
                      make_caller(admin=True))
        self.assertForbidden(r)
        self.api.update_customer.assert_not_called()

    def test_put_other_club_as_super_admin_allowed(self):
        r = self.call(make_event('PUT', f'/customers/{OTHER}', {'customerId': OTHER}, {}),
                      make_caller(super_admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.api.update_customer.assert_called_once()


if __name__ == '__main__':
    unittest.main()
