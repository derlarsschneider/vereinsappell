import base64
import json
import sys
import unittest
from unittest.mock import MagicMock, call
from botocore.exceptions import ClientError

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_docs


def _event(method, path, headers=None, file_name=None, body=None, body_base64=False):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': headers or {},
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
    return _event(method, path, headers={'password': 'testpw'}, **kwargs)


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
        response = api_docs.get_docs(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.list_objects_v2.assert_called_once_with(
            Bucket='test-bucket', Prefix='docs/'
        )

    def test_get_docs_wrong_password_returns_401_no_s3_call(self):
        event = _event('GET', '/docs', headers={'password': 'bad'})
        response = api_docs.get_docs(event)
        self.assertEqual(response['statusCode'], 401)
        self.mock_s3.list_objects_v2.assert_not_called()

    def test_get_docs_strips_prefix_from_names(self):
        self.mock_s3.list_objects_v2.return_value = {
            'Contents': [{'Key': 'docs/Protokolle/file.pdf'}]
        }
        event = _auth_event('GET', '/docs')
        response = api_docs.get_docs(event)
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
        response = api_docs.get_doc(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.get_object.assert_called_once_with(
            Bucket='test-bucket', Key='docs/file.pdf'
        )

    def test_get_doc_with_category(self):
        self.mock_s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: b'content'),
            'ContentType': 'application/pdf',
        }
        event = _auth_event('GET', '/docs/Protokolle/file.pdf', file_name='Protokolle/file.pdf')
        response = api_docs.get_doc(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.get_object.assert_called_once_with(
            Bucket='test-bucket', Key='docs/Protokolle/file.pdf'
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
        response = api_docs.add_doc(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.put_object.assert_called_once()

    def test_add_doc_returns_409_when_file_exists(self):
        self.mock_s3.head_object.return_value = {}  # file exists
        file_content = base64.b64encode(b'pdf content').decode()
        body = {'name': 'existing.pdf', 'file': file_content}
        event = _auth_event('POST', '/docs', body=body)
        response = api_docs.add_doc(event)
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
        response = api_docs.delete_doc(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket='test-bucket', Key='docs/file.pdf'
        )


if __name__ == '__main__':
    unittest.main()
