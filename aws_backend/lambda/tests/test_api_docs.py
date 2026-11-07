import base64
import json
import sys
import unittest
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_docs
from authz import Caller

APP_ID = 'app-123'
PREFIX = f'{APP_ID}/docs'


def _event(method, path, headers=None, file_name=None, body=None, body_base64=False):
    h = {'applicationid': APP_ID}
    if headers:
        h.update(headers)
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': h,
        'pathParameters': {},
    }
    if file_name:
        event['pathParameters']['fileName'] = file_name
    if body:
        if body_base64:
            event['body'] = base64.b64encode(json.dumps(body).encode()).decode()
            event['isBase64Encoded'] = True
        else:
            event['body'] = json.dumps(body)
    return event


def _auth_event(method, path, **kwargs):
    return _event(method, path, headers={'applicationid': APP_ID, 'password': 'testpw'}, **kwargs)


def _not_found_error():
    return ClientError({'Error': {'Code': '404', 'Message': 'Not Found'}}, 'HeadObject')


class TestCheckPassword(unittest.TestCase):
    def setUp(self):
        api_docs.DOCS_PASSWORD = 'testpw'

    def test_correct_password(self):
        event = {'headers': {'password': 'testpw'}}
        self.assertTrue(api_docs._check_password(event))

    def test_wrong_password(self):
        event = {'headers': {'password': 'wrong'}}
        self.assertFalse(api_docs._check_password(event))

    def test_no_password(self):
        event = {'headers': {}}
        self.assertFalse(api_docs._check_password(event))


class TestGetDocs(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        api_docs.s3 = self.mock_s3
        api_docs.s3_bucket_name = 'test-bucket'
        api_docs.DOCS_PASSWORD = 'testpw'

    def test_get_docs_calls_list_objects_with_prefix(self):
        self.mock_s3.list_objects_v2.return_value = {'Contents': []}
        event = _auth_event('GET', '/docs')
        response = api_docs.get_docs(event, PREFIX)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.list_objects_v2.assert_called_once_with(
            Bucket='test-bucket', Prefix=f'{PREFIX}/'
        )

    def test_get_docs_wrong_password_returns_401_no_s3_call(self):
        event = _event('GET', '/docs', headers={'applicationid': APP_ID, 'password': 'bad'})
        response = api_docs.get_docs(event, PREFIX)
        self.assertEqual(response['statusCode'], 401)
        self.mock_s3.list_objects_v2.assert_not_called()

    def test_get_docs_strips_prefix_from_names(self):
        self.mock_s3.list_objects_v2.return_value = {
            'Contents': [{'Key': f'{PREFIX}/Protokolle/file.pdf'}]
        }
        event = _auth_event('GET', '/docs')
        response = api_docs.get_docs(event, PREFIX)
        files = json.loads(response['body'])
        self.assertEqual(files[0]['name'], 'Protokolle/file.pdf')


class TestGetDoc(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        api_docs.s3 = self.mock_s3
        api_docs.s3_bucket_name = 'test-bucket'
        api_docs.DOCS_PASSWORD = 'testpw'
        self.mock_s3.exceptions.ClientError = ClientError

    def test_get_doc_uses_correct_s3_key(self):
        self.mock_s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: b'content'),
            'ContentType': 'application/pdf',
        }
        event = _auth_event('GET', '/docs/file.pdf', file_name='file.pdf')
        response = api_docs.get_doc(event, PREFIX)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.get_object.assert_called_once_with(
            Bucket='test-bucket', Key=f'{PREFIX}/file.pdf'
        )

    def test_get_doc_with_category(self):
        self.mock_s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: b'content'),
            'ContentType': 'application/pdf',
        }
        event = _auth_event('GET', '/docs/Protokolle/file.pdf', file_name='Protokolle/file.pdf')
        response = api_docs.get_doc(event, PREFIX)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.get_object.assert_called_once_with(
            Bucket='test-bucket', Key=f'{PREFIX}/Protokolle/file.pdf'
        )


class TestAddDoc(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        api_docs.s3 = self.mock_s3
        api_docs.s3_bucket_name = 'test-bucket'
        api_docs.DOCS_PASSWORD = 'testpw'
        self.mock_s3.exceptions.ClientError = ClientError

    def test_add_doc_uploads_when_not_exists(self):
        self.mock_s3.head_object.side_effect = _not_found_error()
        self.mock_s3.put_object.return_value = {}
        file_content = base64.b64encode(b'pdf content').decode()
        body = {'name': 'test.pdf', 'file': file_content}
        event = _auth_event('POST', '/docs', body=body)
        response = api_docs.add_doc(event, PREFIX)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.put_object.assert_called_once()

    def test_add_doc_returns_409_when_file_exists(self):
        self.mock_s3.head_object.return_value = {}
        file_content = base64.b64encode(b'pdf content').decode()
        body = {'name': 'existing.pdf', 'file': file_content}
        event = _auth_event('POST', '/docs', body=body)
        response = api_docs.add_doc(event, PREFIX)
        self.assertEqual(response['statusCode'], 409)
        self.mock_s3.put_object.assert_not_called()


class TestDeleteDoc(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        api_docs.s3 = self.mock_s3
        api_docs.s3_bucket_name = 'test-bucket'
        api_docs.DOCS_PASSWORD = 'testpw'

    def test_delete_doc_calls_delete_object_with_correct_key(self):
        self.mock_s3.delete_object.return_value = {}
        event = _auth_event('DELETE', '/docs/file.pdf', file_name='file.pdf')
        response = api_docs.delete_doc(event, PREFIX)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket='test-bucket', Key=f'{PREFIX}/file.pdf'
        )


def _caller(is_admin=False):
    return Caller(application_id=APP_ID, member_id='m1', is_admin=is_admin,
                  is_spiess=False, is_super_admin=False)


class TestHandleDocsAuthorization(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        api_docs.s3 = self.mock_s3
        api_docs.s3_bucket_name = 'test-bucket'
        api_docs.DOCS_PASSWORD = 'testpw'
        self.mock_s3.exceptions.ClientError = ClientError

    def test_no_password_configured_denies_all(self):
        for configured in ('', None):
            api_docs.DOCS_PASSWORD = configured
            for pw in ('', None, 'geheim123'):
                headers = {'applicationid': APP_ID}
                if pw is not None:
                    headers['password'] = pw
                with patch.object(api_docs, 'get_caller', return_value=_caller(True)):
                    for method, path in (('GET', '/docs'), ('GET', '/docs/a.pdf'),
                                         ('POST', '/docs'), ('DELETE', '/docs/a.pdf')):
                        event = _event(method, path, headers=headers, file_name='a.pdf',
                                       body={'name': 'a.pdf', 'file': ''} if method == 'POST' else None)
                        response = api_docs.handle_docs(event, None)
                        self.assertEqual(response['statusCode'], 401, (configured, pw, method, path))
        self.mock_s3.put_object.assert_not_called()
        self.mock_s3.delete_object.assert_not_called()

    def test_upload_as_non_admin_forbidden(self):
        body = {'name': 'a.pdf', 'file': base64.b64encode(b'x').decode()}
        with patch.object(api_docs, 'get_caller', return_value=_caller(False)):
            response = api_docs.handle_docs(_auth_event('POST', '/docs', body=body), {})
        self.assertEqual(response['statusCode'], 403)
        self.mock_s3.put_object.assert_not_called()

    def test_delete_as_non_admin_forbidden(self):
        with patch.object(api_docs, 'get_caller', return_value=_caller(False)):
            response = api_docs.handle_docs(
                _auth_event('DELETE', '/docs/a.pdf', file_name='a.pdf'), {})
        self.assertEqual(response['statusCode'], 403)
        self.mock_s3.delete_object.assert_not_called()

    def test_upload_as_admin_with_password_ok(self):
        self.mock_s3.head_object.side_effect = _not_found_error()
        body = {'name': 'a.pdf', 'file': base64.b64encode(b'x').decode()}
        with patch.object(api_docs, 'get_caller', return_value=_caller(True)):
            response = api_docs.handle_docs(_auth_event('POST', '/docs', body=body), {})
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.put_object.assert_called_once()

    def test_list_as_member_with_password_ok(self):
        self.mock_s3.list_objects_v2.return_value = {'Contents': []}
        with patch.object(api_docs, 'get_caller') as gc:
            response = api_docs.handle_docs(_auth_event('GET', '/docs'), {})
        self.assertEqual(response['statusCode'], 200)
        gc.assert_not_called()


if __name__ == '__main__':
    unittest.main()
