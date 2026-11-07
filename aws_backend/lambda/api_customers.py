import base64
import ipaddress
import json
import os
import socket
import urllib.parse
import urllib.request
import uuid
import boto3

_dynamodb = boto3.resource('dynamodb')
_customers_table = _dynamodb.Table(os.environ.get('CUSTOMERS_TABLE_NAME', ''))
_members_table_ref = _dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))
_s3 = boto3.client('s3')
_s3_bucket_name = os.environ.get('S3_BUCKET_NAME', '')


def table():
    return _customers_table


def _members_table():
    return _members_table_ref


ALL_SCREEN_KEYS = ['termine', 'marschbefehl', 'strafen', 'dokumente', 'galerie', 'schere_stein_papier']

_AD_BANNER_PREFIX = 'ad_banner'


def _upload_ad_banner(customer_id: str, image_bytes: bytes, content_type: str = 'image/jpeg') -> str:
    key = f'{customer_id}/{_AD_BANNER_PREFIX}/banner.jpg'
    _s3.put_object(
        Bucket=_s3_bucket_name,
        Key=key,
        Body=image_bytes,
        ContentType=content_type,
    )
    return key


def _presigned_url_for_key(key: str, expiry: int = 604800) -> str:
    return _s3.generate_presigned_url(
        'get_object',
        Params={'Bucket': _s3_bucket_name, 'Key': key},
        ExpiresIn=expiry,
    )
API_BASE_URL = os.environ.get('API_BASE_URL', '')


def list_customers():
    t = table()
    items = []
    response = t.scan()
    items.extend(response.get('Items', []))
    while 'LastEvaluatedKey' in response:
        response = t.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response.get('Items', []))

    for item in items:
        s3_key = item.get('ad_banner_s3_key', '')
        if s3_key:
            item['ad_banner_image_url'] = _presigned_url_for_key(s3_key)

    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }


MAX_BANNER_BYTES = 5 * 1024 * 1024


class InvalidImageUrl(ValueError):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise InvalidImageUrl('redirects are not allowed')


def _build_opener():
    return urllib.request.build_opener(_NoRedirect)


def _fetch_banner_image(url):
    """Download a banner image from a public https host (SSRF-safe).

    Known limitation: DNS is resolved here and again by the opener (rebinding TOCTOU).
    """
    try:
        parsed = urllib.parse.urlparse(url)
        host = parsed.hostname
        port = parsed.port
    except ValueError:
        raise InvalidImageUrl('malformed url')
    if parsed.scheme != 'https' or not host or parsed.username is not None or port not in (None, 443):
        raise InvalidImageUrl('url not allowed')
    if host.lower() == 'localhost':
        raise InvalidImageUrl('host not allowed')
    try:
        ipaddress.ip_address(host.strip('[]'))
        raise InvalidImageUrl('ip literals not allowed')
    except ValueError as e:
        if isinstance(e, InvalidImageUrl):
            raise
    try:
        infos = socket.getaddrinfo(host, 443)
    except OSError:
        raise InvalidImageUrl('host does not resolve')
    if not infos:
        raise InvalidImageUrl('host does not resolve')
    for info in infos:
        addr = info[4][0].split('%')[0]
        if not ipaddress.ip_address(addr).is_global:
            raise InvalidImageUrl('host resolves to non-public address')

    try:
        with _build_opener().open(url, timeout=10) as resp:  # noqa: S310
            if not str(resp.headers.get('Content-Type', '')).lower().startswith('image/'):
                raise InvalidImageUrl('not an image')
            data = resp.read(MAX_BANNER_BYTES + 1)
    except InvalidImageUrl:
        raise
    except Exception as e:
        print(f"⚠️ banner download failed: {type(e).__name__}: {e}")
        raise InvalidImageUrl('download failed')
    if len(data) > MAX_BANNER_BYTES:
        raise InvalidImageUrl('image too large')
    return data


def update_customer(event):
    customer_id = event['pathParameters']['customerId']
    body = json.loads(event['body'])

    update_expr = 'SET application_name = :name, active_screens = :screens'
    expr_values = {
        ':name': body.get('application_name', ''),
        ':screens': body.get('active_screens', ALL_SCREEN_KEYS),
    }
    logo = body.get('application_logo', '')
    if logo:
        update_expr += ', application_logo = :logo'
        expr_values[':logo'] = logo

    paypal_account = body.get('paypal_account', '')
    if paypal_account:
        update_expr += ', paypal_account = :paypal'
        expr_values[':paypal'] = paypal_account

    ad_type = body.get('ad_type', 'none')
    update_expr += ', ad_type = :ad_type'
    expr_values[':ad_type'] = ad_type

    # Upload ad banner image to S3 (from base64 data or source URL) and store the S3 key.
    image_data_b64 = body.get('ad_banner_image_data', '')
    image_source_url = body.get('ad_banner_image_source_url', '')
    if image_data_b64:
        image_bytes = base64.b64decode(image_data_b64)
        s3_key = _upload_ad_banner(customer_id, image_bytes)
        update_expr += ', ad_banner_s3_key = :ad_banner_s3_key'
        expr_values[':ad_banner_s3_key'] = s3_key
    elif image_source_url:
        try:
            image_bytes = _fetch_banner_image(image_source_url)
        except InvalidImageUrl:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Ungültige Bild-URL'})}
        s3_key = _upload_ad_banner(customer_id, image_bytes)
        update_expr += ', ad_banner_s3_key = :ad_banner_s3_key'
        expr_values[':ad_banner_s3_key'] = s3_key

    for field in ('ad_banner_link_url', 'ad_admob_publisher_id', 'ad_admob_ad_unit_id'):
        value = body.get(field, '')
        if value:
            update_expr += f', {field} = :{field}'
            expr_values[f':{field}'] = value

    table().update_item(
        Key={'application_id': customer_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Verein aktualisiert'})
    }


def create_customer(event):
    body = json.loads(event['body'])
    application_id = str(uuid.uuid4())
    application_name = body['application_name']
    api_url = body.get('api_url') or API_BASE_URL
    application_logo = body.get('application_logo', '')
    active_screens = body.get('active_screens', ALL_SCREEN_KEYS)
    # Fresh id per club: never copy the caller's (super admin) memberId.
    new_member_id = str(uuid.uuid4())
    requesting_member_name = f'Lars ({application_name})'

    item = {
        'application_id': application_id,
        'application_name': application_name,
        'api_url': api_url,
        'application_logo': application_logo,
        'active_screens': active_screens,
        'paypal_account': body.get('paypal_account', 'LarsSchiller1911'),
    }
    table().put_item(Item=item)

    _members_table().put_item(Item={
        'applicationId': application_id,
        'memberId': new_member_id,
        'isAdmin': True,
        'isSuperAdmin': True,
        'isActive': True,
        'name': requesting_member_name,
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            **item,
            'member_id': new_member_id,
            'api_base_url': API_BASE_URL,
        })
    }


def get_customer_by_id(event, context):
    customer_id = event['pathParameters']['customerId']

    response = table().get_item(
        Key={'application_id': customer_id}
    )

    item = response.get('Item')

    if not item:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Verein nicht gefunden'})
        }

    s3_key = item.get('ad_banner_s3_key', '')
    if s3_key:
        item['ad_banner_image_url'] = _presigned_url_for_key(s3_key)

    return {
        'statusCode': 200,
        'body': json.dumps(item)
    }
