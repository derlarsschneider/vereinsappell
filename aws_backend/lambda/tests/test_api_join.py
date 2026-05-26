import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault('boto3', MagicMock())

sys.path.insert(0, '.')
import api_join


def _club_event(body):
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/join/club'}},
        'headers': {'origin': 'https://vereinsappell.web.app'},
        'body': json.dumps(body),
    }


def _member_event(body):
    return {
        'requestContext': {'http': {'method': 'POST', 'path': '/join/member'}},
        'headers': {'origin': 'https://vereinsappell.web.app'},
        'body': json.dumps(body),
    }


class TestHandleJoinClub(unittest.TestCase):
    def setUp(self):
        api_join.ses = MagicMock()
        os.environ['CONTACT_EMAIL'] = 'info@vereinsappell.de'

    def test_returns_200_on_valid_payload(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Schützenverein Test',
            'contact': 'Max Mustermann',
            'email': 'max@example.com',
        })
        response = api_join.handle_join_club(event, {})
        self.assertEqual(response['statusCode'], 200)

    def test_sends_email_with_club_details(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Schützenverein Test',
            'contact': 'Max Mustermann',
            'email': 'max@example.com',
            'phone': '+49 123 456',
            'message': 'Wir haben 42 Mitglieder.',
        })
        api_join.handle_join_club(event, {})
        call_kwargs = api_join.ses.send_email.call_args[1]
        body_text = call_kwargs['Message']['Body']['Text']['Data']
        self.assertIn('Schützenverein Test', body_text)
        self.assertIn('Max Mustermann', body_text)
        self.assertIn('max@example.com', body_text)

    def test_returns_400_when_required_field_missing(self):
        event = _club_event({'clubName': 'Test'})  # missing contact and email
        response = api_join.handle_join_club(event, {})
        self.assertEqual(response['statusCode'], 400)

    def test_has_cors_header(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _club_event({
            'clubName': 'Test', 'contact': 'Test', 'email': 'test@test.de'
        })
        response = api_join.handle_join_club(event, {})
        self.assertIn('Access-Control-Allow-Origin', response['headers'])


class TestHandleJoinMember(unittest.TestCase):
    def setUp(self):
        api_join.ses = MagicMock()
        os.environ['CONTACT_EMAIL'] = 'info@vereinsappell.de'

    def test_returns_200_on_valid_payload(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _member_event({
            'name': 'Max Mustermann',
            'clubName': 'Schützenverein Test',
            'email': 'max@example.com',
        })
        response = api_join.handle_join_member(event, {})
        self.assertEqual(response['statusCode'], 200)

    def test_sends_email_with_member_details(self):
        api_join.ses.send_email.return_value = {'MessageId': 'abc123'}
        event = _member_event({
            'name': 'Max Mustermann',
            'clubName': 'Schützenverein Test',
            'email': 'max@example.com',
            'message': 'Ich möchte beitreten.',
        })
        api_join.handle_join_member(event, {})
        call_kwargs = api_join.ses.send_email.call_args[1]
        body_text = call_kwargs['Message']['Body']['Text']['Data']
        self.assertIn('Max Mustermann', body_text)
        self.assertIn('Schützenverein Test', body_text)

    def test_returns_400_when_required_field_missing(self):
        event = _member_event({'name': 'Max'})  # missing clubName and email
        response = api_join.handle_join_member(event, {})
        self.assertEqual(response['statusCode'], 400)
