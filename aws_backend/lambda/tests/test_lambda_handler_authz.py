import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

os.environ.setdefault('MEMBERS_TABLE_NAME', 'members-test')
os.environ.setdefault('AWS_DEFAULT_REGION', 'eu-central-1')

# Stub heavy dependencies only while importing, so the stubs do not leak into other test modules.
_stubs = {
    'boto3': MagicMock(),
    'boto3.dynamodb': MagicMock(),
    'boto3.dynamodb.conditions': MagicMock(),
    'push_notifications': MagicMock(),
    'error_handler': MagicMock(),
    'api_members': MagicMock(),
    'api_docs': MagicMock(),
}
sys.path.insert(0, '.')
with patch.dict(sys.modules, _stubs):
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


class TestMonitoringRoutes(AuthzTestCase):
    READ_ROUTES = {
        '/monitoring/stats': 'handle_monitoring',
        '/monitoring/startup': 'handle_startup_stats',
        '/monitoring/perf': 'handle_perf_stats',
        '/monitoring/errors': 'handle_errors',
    }

    def setUp(self):
        self.api = MagicMock()
        for name in list(self.READ_ROUTES.values()) + ['handle_timing']:
            getattr(self.api, name).return_value = {'statusCode': 200, 'body': '{}'}
        patcher = patch.dict(sys.modules, {'api_monitoring': self.api})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_read_routes_forbidden_for_plain_member(self):
        for path, fn in self.READ_ROUTES.items():
            with self.subTest(path=path):
                self.assertForbidden(self.call(make_event('GET', path), make_caller()))
                getattr(self.api, fn).assert_not_called()

    def test_read_routes_forbidden_for_club_admin(self):
        for path in self.READ_ROUTES:
            with self.subTest(path=path):
                self.assertForbidden(self.call(make_event('GET', path), make_caller(admin=True)))

    def test_read_routes_allowed_for_super_admin(self):
        for path, fn in self.READ_ROUTES.items():
            with self.subTest(path=path):
                r = self.call(make_event('GET', path), make_caller(super_admin=True))
                self.assertEqual(r['statusCode'], 200)
                getattr(self.api, fn).assert_called_once()

    def test_timing_allowed_for_plain_member(self):
        r = self.call(make_event('POST', '/monitoring/timing', body={}), make_caller())
        self.assertEqual(r['statusCode'], 200)
        self.api.handle_timing.assert_called_once()


class TestFinesMarschbefehlPhotoRoutes(AuthzTestCase):
    def setUp(self):
        self.fines = MagicMock()
        self.members = MagicMock()
        self.marsch = MagicMock()
        self.s3 = MagicMock()
        self.fines.query.return_value = {'Items': []}
        self.marsch.query.return_value = {'Items': []}
        self.members.get_item.return_value = {}
        for attr, mock in (('fines_table', self.fines), ('members_table', self.members),
                           ('marschbefehl_table', self.marsch)):
            patcher = patch.object(lambda_handler, attr, mock)
            patcher.start()
            self.addCleanup(patcher.stop)
        for name, rv in (('add_photo', {'statusCode': 200, 'body': '{}'}),
                         ('delete_photo', {'statusCode': 200, 'body': '{}'}),
                         ('get_photos', {'statusCode': 200, 'body': '{}'}),
                         ('add_fine', {'statusCode': 200, 'body': '{}'})):
            patcher = patch.object(lambda_handler, name, return_value=rv)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)

    def fines_event(self, member_id='m1'):
        event = make_event('GET', '/fines')
        event['queryStringParameters'] = {'memberId': member_id}
        return event

    # GET /fines
    def test_get_own_fines_as_plain_member_allowed(self):
        r = self.call(self.fines_event('m1'), make_caller())
        self.assertEqual(r['statusCode'], 200)

    def test_get_fines_of_other_member_as_plain_member_forbidden(self):
        self.assertForbidden(self.call(self.fines_event('m2'), make_caller()))
        self.fines.query.assert_not_called()

    def test_get_fines_of_other_member_as_spiess_allowed(self):
        self.assertEqual(self.call(self.fines_event('m2'), make_caller(spiess=True))['statusCode'], 200)

    def test_get_fines_of_other_member_as_admin_allowed(self):
        self.assertEqual(self.call(self.fines_event('m2'), make_caller(admin=True))['statusCode'], 200)

    # POST /fines
    def test_add_fine_plain_member_forbidden(self):
        self.assertForbidden(self.call(make_event('POST', '/fines', body={}), make_caller()))
        self.add_fine.assert_not_called()

    def test_add_fine_spiess_allowed(self):
        r = self.call(make_event('POST', '/fines', body={}), make_caller(spiess=True))
        self.assertEqual(r['statusCode'], 200)

    def test_add_fine_admin_allowed(self):
        r = self.call(make_event('POST', '/fines', body={}), make_caller(admin=True))
        self.assertEqual(r['statusCode'], 200)

    # DELETE /fines/{id}
    def delete_fine_event(self):
        return make_event('DELETE', '/fines/f1', {'fineId': 'f1'})

    def test_delete_fine_plain_member_forbidden(self):
        self.assertForbidden(self.call(self.delete_fine_event(), make_caller()))
        self.fines.delete_item.assert_not_called()

    def test_delete_fine_spiess_allowed(self):
        r = self.call(self.delete_fine_event(), make_caller(spiess=True))
        self.assertEqual(r['statusCode'], 200)
        self.fines.delete_item.assert_called_once()

    def test_delete_fine_admin_allowed(self):
        r = self.call(self.delete_fine_event(), make_caller(admin=True))
        self.assertEqual(r['statusCode'], 200)

    def test_delete_fine_uses_caller_application_id(self):
        event = self.delete_fine_event()
        event['headers']['applicationid'] = OTHER
        self.call(event, make_caller(spiess=True, application_id=OWN))
        self.fines.delete_item.assert_called_once_with(
            Key={'applicationId': OWN, 'fineId': 'f1'})

    # marschbefehl
    def test_get_marschbefehl_plain_member_allowed(self):
        r = self.call(make_event('GET', '/marschbefehl'), make_caller())
        self.assertEqual(r['statusCode'], 200)

    def test_add_marschbefehl_spiess_forbidden(self):
        self.assertForbidden(self.call(make_event('POST', '/marschbefehl', body={}),
                                       make_caller(spiess=True)))
        self.marsch.put_item.assert_not_called()

    def test_add_marschbefehl_admin_allowed(self):
        body = {'datetime': '2026-01-01', 'text': 't'}
        r = self.call(make_event('POST', '/marschbefehl', body=body), make_caller(admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.marsch.put_item.assert_called_once()

    def test_delete_marschbefehl_non_admin_forbidden(self):
        event = make_event('DELETE', '/marschbefehl')
        event['queryStringParameters'] = {'datetime': 'x'}
        self.assertForbidden(self.call(event, make_caller(spiess=True)))
        self.marsch.delete_item.assert_not_called()

    def test_delete_marschbefehl_admin_allowed(self):
        event = make_event('DELETE', '/marschbefehl')
        event['queryStringParameters'] = {'datetime': 'x'}
        r = self.call(event, make_caller(admin=True))
        self.assertEqual(r['statusCode'], 200)
        self.marsch.delete_item.assert_called_once()

    # photos
    def test_get_photos_plain_member_allowed(self):
        self.assertEqual(self.call(make_event('GET', '/photos'), make_caller())['statusCode'], 200)

    def test_post_photo_plain_member_allowed(self):
        self.assertEqual(self.call(make_event('POST', '/photos', body={}), make_caller())['statusCode'], 200)

    def test_delete_photo_non_admin_forbidden(self):
        event = make_event('DELETE', '/photos/a.jpg', {'proxy': 'a.jpg'})
        self.assertForbidden(self.call(event, make_caller(spiess=True)))
        self.delete_photo.assert_not_called()

    def test_delete_photo_admin_allowed(self):
        event = make_event('DELETE', '/photos/a.jpg', {'proxy': 'a.jpg'})
        self.assertEqual(self.call(event, make_caller(admin=True))['statusCode'], 200)
        self.delete_photo.assert_called_once()


if __name__ == '__main__':
    unittest.main()
