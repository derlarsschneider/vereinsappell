import json
import sys
import unittest
from unittest.mock import MagicMock, patch, call

sys.modules.setdefault('boto3', MagicMock())
sys.modules.setdefault('push_notifications', MagicMock())
sys.path.insert(0, '.')
import api_feedback

APP_ID = 'app-123'
SUPER_ADMIN_APP_ID = 'app-super'
SUPER_ADMIN_MEMBER_ID = 'superadmin1'


def _event(method, path, member_id='user1', body=None, feedback_id=None):
    event = {
        'requestContext': {'http': {'method': method, 'path': path}},
        'headers': {'applicationid': APP_ID, 'memberid': member_id},
        'pathParameters': {},
    }
    if feedback_id:
        event['pathParameters']['feedbackId'] = feedback_id
    if body:
        event['body'] = json.dumps(body)
    return event


class TestPostFeedback(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table
        api_feedback.SUPER_ADMIN_APPLICATION_ID = SUPER_ADMIN_APP_ID
        api_feedback.SUPER_ADMIN_MEMBER_ID = SUPER_ADMIN_MEMBER_ID
        api_feedback.ADMIN_EMAIL = 'test@example.com'

        self.mock_members_table.get_item.side_effect = lambda Key: {
            'Item': {'name': 'Max', 'memberId': Key['memberId'], 'token': 'fcm-token'}
        }

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_saves_item(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={'message': 'Test Feedback'})
        response = api_feedback.post_feedback(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.put_item.assert_called_once()
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['message'], 'Test Feedback')
        self.assertEqual(item['applicationId'], APP_ID)

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_sends_push_and_email(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={'message': 'Hi'})
        api_feedback.post_feedback(event)
        mock_push.assert_called_once()
        mock_email.assert_called_once()

    @patch('api_feedback.send_push_notification')
    @patch('api_feedback._send_ses_email')
    def test_post_feedback_stores_news_fields(self, mock_email, mock_push):
        event = _event('POST', '/feedback', member_id='user1', body={
            'message': 'Juli',
            'newsId': 'news-1',
            'newsTitle': 'Terminplanung',
            'newsQuestion': 'Wann?',
        })
        api_feedback.post_feedback(event)
        item = self.mock_table.put_item.call_args[1]['Item']
        self.assertEqual(item['newsId'], 'news-1')
        self.assertEqual(item['newsQuestion'], 'Wann?')


class TestGetFeedback(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table

        self.items = [
            {'applicationId': APP_ID, 'feedbackId': '1', 'memberId': 'user1', 'message': 'Hello'},
            {'applicationId': APP_ID, 'feedbackId': '2', 'memberId': 'user2', 'message': 'World'},
        ]
        self.mock_table.query.return_value = {'Items': self.items}
        self.mock_table.scan.return_value = {'Items': self.items}

    def test_superadmin_gets_all_feedback(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('GET', '/feedback', member_id='superadmin1')
        response = api_feedback.get_feedback(event)
        self.assertEqual(response['statusCode'], 200)
        body = json.loads(response['body'])
        self.assertEqual(len(body), 2)
        self.mock_table.scan.assert_called_once()

    def test_member_gets_only_own_feedback(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        self.mock_table.query.return_value = {
            'Items': [{'applicationId': APP_ID, 'feedbackId': '1', 'memberId': 'user1', 'message': 'Hello'}]
        }
        event = _event('GET', '/feedback', member_id='user1')
        response = api_feedback.get_feedback(event)
        body = json.loads(response['body'])
        self.assertEqual(len(body), 1)


class TestPostReply(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table

    def test_reply_returns_403_for_non_superadmin(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': False}}
        event = _event('POST', '/feedback/1/reply', member_id='user1',
                       body={'reply': 'Thanks'}, feedback_id='1')
        response = api_feedback.post_reply(event)
        self.assertEqual(response['statusCode'], 403)

    def test_reply_updates_feedback_item(self):
        self.mock_members_table.get_item.return_value = {'Item': {'isSuperAdmin': True}}
        event = _event('POST', '/feedback/1/reply', member_id='superadmin1',
                       body={'reply': 'Danke!'}, feedback_id='1')
        response = api_feedback.post_reply(event)
        self.assertEqual(response['statusCode'], 200)
        self.mock_table.update_item.assert_called_once()


class TestHandleFeedback(unittest.TestCase):
    def setUp(self):
        self.mock_table = MagicMock()
        self.mock_members_table = MagicMock()
        api_feedback.feedback_table = self.mock_table
        api_feedback.members_table = self.mock_members_table
        api_feedback.SUPER_ADMIN_APPLICATION_ID = SUPER_ADMIN_APP_ID
        api_feedback.SUPER_ADMIN_MEMBER_ID = SUPER_ADMIN_MEMBER_ID
        api_feedback.ADMIN_EMAIL = 'test@example.com'

    @patch('api_feedback.post_feedback')
    def test_dispatcher_routes_post_feedback(self, mock_post):
        mock_post.return_value = {'statusCode': 200, 'body': '{}'}
        event = _event('POST', '/feedback', body={'message': 'Hi'})
        response = api_feedback.handle_feedback(event, None)
        mock_post.assert_called_once_with(event)
        self.assertEqual(response['statusCode'], 200)

    @patch('api_feedback.get_feedback')
    def test_dispatcher_routes_get_feedback(self, mock_get):
        mock_get.return_value = {'statusCode': 200, 'body': '[]'}
        event = _event('GET', '/feedback')
        response = api_feedback.handle_feedback(event, None)
        mock_get.assert_called_once_with(event)
        self.assertEqual(response['statusCode'], 200)

    @patch('api_feedback.post_reply')
    def test_dispatcher_routes_post_reply(self, mock_reply):
        mock_reply.return_value = {'statusCode': 200, 'body': '{}'}
        event = _event('POST', '/feedback/1/reply', body={'reply': 'OK'}, feedback_id='1')
        response = api_feedback.handle_feedback(event, None)
        mock_reply.assert_called_once_with(event)
        self.assertEqual(response['statusCode'], 200)

    def test_dispatcher_returns_404_for_unknown_route(self):
        event = _event('DELETE', '/feedback')
        response = api_feedback.handle_feedback(event, None)
        self.assertEqual(response['statusCode'], 404)


if __name__ == '__main__':
    unittest.main()
