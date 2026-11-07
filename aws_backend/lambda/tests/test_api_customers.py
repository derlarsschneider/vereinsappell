import json
import os
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_customers


def _event(method, path, body=None, customer_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {},
        'pathParameters': {},
    }
    if customer_id:
        event['pathParameters']['customerId'] = customer_id
    if body is not None:
        event['body'] = json.dumps(body)
    return event


class TestListCustomers(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_returns_all_clubs(self):
        clubs = [
            {'application_id': 'club1', 'application_name': 'Club 1'},
            {'application_id': 'club2', 'application_name': 'Club 2'},
        ]
        self.mock_table.scan.return_value = {'Items': clubs}
        response = api_customers.list_customers()
        self.assertEqual(response['statusCode'], 200)
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]['application_id'], 'club1')

    def test_handles_pagination(self):
        self.mock_table.scan.side_effect = [
            {'Items': [{'application_id': 'c1'}], 'LastEvaluatedKey': {'application_id': 'c1'}},
            {'Items': [{'application_id': 'c2'}]},
        ]
        response = api_customers.list_customers()
        items = json.loads(response['body'])
        self.assertEqual(len(items), 2)


class TestUpdateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)

    def test_update_customer(self):
        event = _event(
            'PUT', '/customers/club1',
            body={'application_name': 'New Name', 'active_screens': ['termine', 'strafen']},
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.update_item.assert_called_once()
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertEqual(call_kwargs['Key'], {'application_id': 'club1'})

    def test_update_customer_with_logo(self):
        event = _event(
            'PUT', '/customers/club1',
            body={
                'application_name': 'New Name',
                'application_logo': 'abc123',
                'active_screens': ['termine'],
            },
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 200)
        call_kwargs = self.mock_table.update_item.call_args[1]
        self.assertIn(':logo', call_kwargs['ExpressionAttributeValues'])


class TestCreateCustomer(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_customers.table = MagicMock(return_value=self.mock_table)
        api_customers._members_table = MagicMock(return_value=self.mock_members_table)

    def test_create_customer_success(self):
        event = _event(
            'POST', '/customers',
            body={'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = json.loads(response['body'])
        # application_id is a server-generated UUID
        self.assertIn('application_id', item)
        self.assertEqual(len(item['application_id']), 36)  # UUID format

    def test_create_customer_defaults_active_screens(self):
        event = _event(
            'POST', '/customers',
            body={'application_name': 'New Club'},
        )
        response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(len(item['active_screens']), len(api_customers.ALL_SCREEN_KEYS))

    def test_create_customer_uses_api_base_url_default(self):
        with patch.object(api_customers, 'API_BASE_URL', 'https://api.example.com'):
            event = _event(
                'POST', '/customers',
                body={'application_name': 'New Club'},
            )
            response = api_customers.create_customer(event)
        item = json.loads(response['body'])
        self.assertEqual(item['api_url'], 'https://api.example.com')

    def test_create_customer_response_includes_member_id(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        event['headers'] = {'memberid': 'super123'}
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['member_id'], 'super123')

    def test_create_customer_response_includes_api_base_url(self):
        with patch.object(api_customers, 'API_BASE_URL', 'https://api.example.com'):
            event = _event('POST', '/customers', body={'application_name': 'New Club'})
            event['headers'] = {}
            response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['api_base_url'], 'https://api.example.com')

    def test_create_customer_response_member_id_empty_when_no_header(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        # no 'headers' key — must not crash
        event.pop('headers', None)
        response = api_customers.create_customer(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(body['member_id'], '')

    def test_create_customer_adds_creator_as_admin_and_superadmin(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        event['headers'] = {'memberid': 'super123'}
        api_customers.create_customer(event)
        self.mock_members_table.put_item.assert_called_once()
        item = self.mock_members_table.put_item.call_args.kwargs['Item']
        self.assertTrue(item['isAdmin'])
        self.assertTrue(item['isSuperAdmin'])
        self.assertTrue(item['isActive'])
        self.assertEqual(item['memberId'], 'super123')

    def test_create_customer_no_member_created_without_requester(self):
        event = _event('POST', '/customers', body={'application_name': 'New Club'})
        event['headers'] = {}
        api_customers.create_customer(event)
        self.mock_members_table.put_item.assert_not_called()


class _FakeResponse:
    def __init__(self, data=b'img', content_type='image/png'):
        self._data = data
        self.headers = {'Content-Type': content_type}

    def read(self, n=-1):
        return self._data if n is None or n < 0 else self._data[:n]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _addrinfo(ip):
    return [(2, 1, 6, '', (ip, 443))]


class TestFetchBannerImage(unittest.TestCase):
    def _fetch(self, url, ip='93.184.216.34', response=None):
        opener = MagicMock()
        opener.open.return_value = response or _FakeResponse()
        with patch.object(api_customers.socket, 'getaddrinfo', return_value=_addrinfo(ip)), \
                patch.object(api_customers, '_build_opener', return_value=opener):
            return api_customers._fetch_banner_image(url)

    def test_rejects_http(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('http://example.com/a.png')

    def test_rejects_file_scheme(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('file:///etc/passwd')

    def test_rejects_ip_literal(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://93.184.216.34/a.png')

    def test_rejects_localhost(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://localhost/a.png')

    def test_rejects_non_443_port(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com:8443/a.png')

    def test_rejects_private_resolution(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com/a.png', ip='10.0.0.1')

    def test_rejects_link_local(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com/a.png', ip='169.254.169.254')

    def test_rejects_loopback(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com/a.png', ip='127.0.0.1')

    def test_rejects_non_image_content_type(self):
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com/a.png', response=_FakeResponse(content_type='text/plain'))

    def test_rejects_oversized(self):
        big = b'x' * (5 * 1024 * 1024 + 1)
        with self.assertRaises(api_customers.InvalidImageUrl):
            self._fetch('https://example.com/a.png', response=_FakeResponse(data=big))

    def test_accepts_public_https_image(self):
        self.assertEqual(self._fetch('https://example.com/a.png'), b'img')

    def test_update_customer_invalid_url_returns_400_and_no_db_write(self):
        mock_table = MagicMock()
        api_customers.table = MagicMock(return_value=mock_table)
        event = _event(
            'PUT', '/customers/club1',
            body={'application_name': 'X', 'ad_banner_image_source_url': 'file:///etc/passwd'},
            customer_id='club1',
        )
        response = api_customers.update_customer(event)
        self.assertEqual(response['statusCode'], 400)
        self.assertEqual(json.loads(response['body']), {'error': 'Ungültige Bild-URL'})
        mock_table.update_item.assert_not_called()


class TestBannerRedirectAndDns(unittest.TestCase):
    def test_real_opener_refuses_redirect(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header('Location', 'http://169.254.169.254/')
                self.send_header('Content-Length', '0')
                self.end_headers()

            def log_message(self, *args):
                pass

        server = HTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            with self.assertRaises(api_customers.InvalidImageUrl):
                api_customers._build_opener().open(f'http://127.0.0.1:{server.server_port}/', timeout=5)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_rejects_mixed_public_and_private_resolution(self):
        opener = MagicMock()
        infos = _addrinfo('93.184.216.34') + _addrinfo('10.0.0.1')
        with patch.object(api_customers.socket, 'getaddrinfo', return_value=infos), \
                patch.object(api_customers, '_build_opener', return_value=opener):
            with self.assertRaises(api_customers.InvalidImageUrl):
                api_customers._fetch_banner_image('https://example.com/a.png')
        opener.open.assert_not_called()
