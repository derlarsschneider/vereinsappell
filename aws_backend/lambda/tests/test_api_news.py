import json
import sys
import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timedelta

sys.modules.setdefault('boto3', MagicMock())
sys.path.insert(0, '.')
import api_news

APP_ID = 'app-123'
SUPER_ADMIN_ID = 'superadmin1'
FUTURE = (datetime.utcnow() + timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%S')
PAST = (datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%S')


def _event(method, path, member_id='user1', body=None, news_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': APP_ID, 'memberid': member_id},
        'pathParameters': {},
    }
    if news_id:
        event['pathParameters']['newsId'] = news_id
    if body:
        event['body'] = json.dumps(body)
    return event


class TestGetNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        api_news.news_table = self.mock_table

    def test_get_news_returns_non_expired_items(self):
        self.mock_table.scan.return_value = {
            'Items': [
                {'newsId': '1', 'title': 'Active', 'expiresAt': FUTURE},
                {'newsId': '2', 'title': 'Expired', 'expiresAt': PAST},
                {'newsId': '3', 'title': 'No expiry'},
            ]
        }
        response = api_news.get_news()
        body = json.loads(response['body'])
        titles = [i['title'] for i in body]
        self.assertIn('Active', titles)
        self.assertIn('No expiry', titles)
        self.assertNotIn('Expired', titles)

    def test_get_news_sorted_newest_first(self):
        self.mock_table.scan.return_value = {
            'Items': [
                {'newsId': '1', 'title': 'Old', 'date': '2026-01-01T00:00:00'},
                {'newsId': '2', 'title': 'New', 'date': '2026-06-01T00:00:00'},
            ]
        }
        response = api_news.get_news()
        body = json.loads(response['body'])
        self.assertEqual(body[0]['title'], 'New')


class TestPostNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_news.news_table = self.mock_table
        api_news.members_table = self.mock_members_table

    def test_post_news_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('POST', '/news', member_id='user1', body={'title': 'x', 'body': 'y'})
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 403)
        self.mock_table.put_item.assert_not_called()

    def test_post_news_saves_item_as_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/news', member_id=SUPER_ADMIN_ID, body={
            'title': 'Test', 'body': 'Text', 'expiresAt': FUTURE,
            'question': 'Wie findet ihr das?', 'questionOptions': ['Gut', 'Schlecht'],
        })
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['title'], 'Test')
        self.assertEqual(item['question'], 'Wie findet ihr das?')
        self.assertEqual(item['questionOptions'], ['Gut', 'Schlecht'])

    def test_post_news_without_optional_fields(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/news', member_id=SUPER_ADMIN_ID, body={'title': 'x', 'body': 'y'})
        response = api_news.post_news(event)
        self.assertEqual(response['statusCode'], 200)


class TestDeleteNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_news.news_table = self.mock_table
        api_news.members_table = self.mock_members_table

    def test_delete_news_as_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('DELETE', '/news/abc', member_id=SUPER_ADMIN_ID, news_id='abc')
        response = api_news.delete_news(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.delete_item.assert_called_once_with(Key={'newsId': 'abc'})

    def test_delete_news_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('DELETE', '/news/abc', member_id='user1', news_id='abc')
        response = api_news.delete_news(event)
        self.assertEqual(response['statusCode'], 403)


class TestHandleNews(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_news.news_table = self.mock_table
        api_news.members_table = self.mock_members_table

    def test_get_delegates_to_get_news(self):
        self.mock_table.scan.return_value = {'Items': []}
        event = _event('GET', '/news')
        response = api_news.handle_news(event, {})
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertIsInstance(body, list)

    def test_post_as_superadmin_creates_news(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/news', member_id=SUPER_ADMIN_ID, body={'title': 'x', 'body': 'y'})
        response = api_news.handle_news(event, {})
        self.assertEqual(response['statusCode'], 200)

    def test_delete_routes_to_delete_news(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('DELETE', '/news/abc', member_id=SUPER_ADMIN_ID, news_id='abc')
        response = api_news.handle_news(event, {})
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.delete_item.assert_called_once_with(Key={'newsId': 'abc'})

    def test_unknown_method_returns_404(self):
        event = _event('PUT', '/news')
        response = api_news.handle_news(event, {})
        self.assertEqual(response['statusCode'], 404)


if __name__ == '__main__':
    unittest.main()
