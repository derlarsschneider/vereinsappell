import base64
import io
import json
import sys
import unittest
from unittest.mock import MagicMock, patch, call

_boto3_mock = MagicMock()
sys.modules.setdefault('boto3', _boto3_mock)
sys.modules.setdefault('boto3.dynamodb', MagicMock())
sys.modules.setdefault('boto3.dynamodb.conditions', MagicMock())
sys.modules['push_notifications'] = MagicMock()
sys.modules['error_handler'] = MagicMock()
sys.modules['api_members'] = MagicMock()
sys.modules['api_docs'] = MagicMock()

sys.path.insert(0, '.')
import lambda_handler

APP_ID = 'app-123'


def _upload_event(filename, file_bytes):
    body = json.dumps({'name': filename, 'file': base64.b64encode(file_bytes).decode()})
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/photos'}},
        'headers': {'applicationid': APP_ID},
        'body': body,
    }


class TestAddPhoto(unittest.TestCase):
    def setUp(self):
        self.mock_s3 = MagicMock()
        _boto3_mock.client.return_value = self.mock_s3
        self.mock_s3.exceptions.ClientError = Exception
        # Simulate file not existing yet
        self.mock_s3.head_object.side_effect = Exception('404')

    @patch('lambda_handler._generate_thumbnail', return_value=b'thumb')
    def test_stores_both_img_and_thumbnail(self, _mock_thumb):
        image_bytes = b'fake-image'
        event = _upload_event('photo.jpg', image_bytes)
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        put_calls = self.mock_s3.put_object.call_args_list
        keys = [c.kwargs['Key'] for c in put_calls]
        self.assertIn(f'{APP_ID}/photos/img/photo.jpg', keys)
        self.assertIn(f'{APP_ID}/photos/thumbnails/photo.jpg', keys)

    @patch('lambda_handler._generate_thumbnail', return_value=b'thumb')
    def test_converts_non_jpg_extension_to_jpg(self, _mock_thumb):
        image_bytes = b'fake-image'
        event = _upload_event('photo.png', image_bytes)
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 200)
        put_calls = self.mock_s3.put_object.call_args_list
        keys = [c.kwargs['Key'] for c in put_calls]
        self.assertIn(f'{APP_ID}/photos/img/photo.jpg', keys)

    def test_returns_409_for_duplicate(self):
        self.mock_s3.head_object.side_effect = None  # file exists
        event = _upload_event('photo.jpg', b'img')
        response = lambda_handler.add_photo(event, APP_ID)
        self.assertEqual(response['statusCode'], 409)
        self.mock_s3.put_object.assert_not_called()


if __name__ == '__main__':
    unittest.main()
