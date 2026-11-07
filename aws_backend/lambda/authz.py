import json
import os
from dataclasses import dataclass

import boto3

dynamodb = boto3.resource('dynamodb')
members_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME'))


@dataclass(frozen=True)
class Caller:
    application_id: str
    member_id: str
    is_admin: bool
    is_spiess: bool
    is_super_admin: bool

    def can_manage_club(self, customer_id: str) -> bool:
        return self.is_super_admin or (self.is_admin and customer_id == self.application_id)


def get_caller(event: dict) -> Caller:
    """Build the caller from request headers and a single members-table lookup."""
    headers = event.get('headers') or {}
    application_id = headers.get('applicationid') or ''
    member_id = headers.get('memberid') or ''
    item = {}
    if application_id and member_id:
        response = members_table.get_item(
            Key={'applicationId': application_id, 'memberId': member_id})
        item = response.get('Item') or {}
    return Caller(
        application_id=application_id,
        member_id=member_id,
        is_admin=bool(item.get('isAdmin', False)),
        is_spiess=bool(item.get('isSpiess', False)),
        is_super_admin=bool(item.get('isSuperAdmin', False)),
    )


def forbidden(headers: dict) -> dict:
    return {
        **headers,
        'statusCode': 403,
        'body': json.dumps({'error': 'Nicht berechtigt'}),
    }
