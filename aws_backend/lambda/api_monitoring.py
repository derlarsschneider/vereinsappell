import boto3
import json
import os
import time
from datetime import datetime, timedelta


def _build_name_maps(app_ids):
    dynamodb = boto3.resource('dynamodb')

    club_table = dynamodb.Table(os.environ.get('CUSTOMERS_TABLE_NAME', ''))
    club_resp = club_table.scan(ProjectionExpression='application_id, application_name')
    club_names = {c['application_id']: c.get('application_name', c['application_id'])
                  for c in club_resp.get('Items', [])}

    member_table = dynamodb.Table(os.environ.get('MEMBERS_TABLE_NAME', ''))
    member_names = {}
    scan_kwargs = {
        'ProjectionExpression': 'applicationId, memberId, #n',
        'ExpressionAttributeNames': {'#n': 'name'},
    }
    while True:
        member_resp = member_table.scan(**scan_kwargs)
        for c in member_resp.get('Items', []):
            key = (c['applicationId'], c['memberId'])
            member_names[key] = c.get('name', c['memberId'])
        last = member_resp.get('LastEvaluatedKey')
        if not last:
            break
        scan_kwargs['ExclusiveStartKey'] = last

    return club_names, member_names


def handle_monitoring(event, context):
    params = event.get('queryStringParameters') or {}
    timeframe = params.get('timeframe', 'day')
    
    logs = boto3.client('logs')
    # Use the function's own log group name if not provided
    log_group_name = os.environ.get('LAMBDA_LOG_GROUP_NAME') or context.log_group_name
    
    # Calculate start time
    now = datetime.utcnow()
    if timeframe == 'minute':
        start_time = now - timedelta(minutes=1)
    elif timeframe == 'hour':
        start_time = now - timedelta(hours=1)
    elif timeframe == 'day':
        start_time = now - timedelta(days=1)
    elif timeframe == 'week':
        start_time = now - timedelta(weeks=1)
    elif timeframe == 'month':
        start_time = now - timedelta(days=30)
    elif timeframe == 'year':
        start_time = now - timedelta(days=365)
    else:
        start_time = now - timedelta(days=1)

    start_timestamp = int(start_time.timestamp())
    end_timestamp = int(now.timestamp())

    # Query: Aggregated Stats
    # We use a combined query to get both calls per club and active members if possible, 
    # or just fetch raw structured logs and aggregate here for simplicity/speed in this demo.
    query = f"""
    fields applicationId, memberId, path, @timestamp
    | filter log_type = "api_access"
    | sort @timestamp desc
    """
    
    try:
        start_query_response = logs.start_query(
            logGroupName=log_group_name,
            startTime=start_timestamp,
            endTime=end_timestamp,
            queryString=query,
            limit=1000
        )
        
        query_id = start_query_response['queryId']
        
        # Wait for results (with a timeout)
        response = None
        for _ in range(10):
            response = logs.get_query_results(queryId=query_id)
            if response['status'] in ['Complete', 'Failed', 'Cancelled']:
                break
            time.sleep(0.5)
            
        if response['status'] != 'Complete':
            return {'statusCode': 500, 'body': json.dumps({'error': f'Query failed: {response["status"]}'})}
            
        # Process results
        results = response['results']
        
        calls_per_club = {}
        active_members = {}
        calls_per_endpoint = {}  # (app_id, path) -> count
        calls_per_member = {}    # (app_id, mem_id) -> count

        for row in results:
            app_id = next((item['value'] for item in row if item['field'] == 'applicationId'), 'unknown')
            mem_id = next((item['value'] for item in row if item['field'] == 'memberId'), 'unknown')
            path   = next((item['value'] for item in row if item['field'] == 'path'), 'unknown')

            calls_per_club[app_id] = calls_per_club.get(app_id, 0) + 1

            if app_id not in active_members:
                active_members[app_id] = {}
            active_members[app_id][mem_id] = active_members[app_id].get(mem_id, 0) + 1

            ep_key = (app_id, path)
            calls_per_endpoint[ep_key] = calls_per_endpoint.get(ep_key, 0) + 1

            mem_key = (app_id, mem_id)
            calls_per_member[mem_key] = calls_per_member.get(mem_key, 0) + 1

        app_ids = set(calls_per_club.keys())
        club_names, member_names = _build_name_maps(app_ids)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'calls_per_club': [
                    {'applicationId': k, 'clubName': club_names.get(k, k), 'count': v}
                    for k, v in calls_per_club.items()
                ],
                'active_members': [
                    {'applicationId': app_id, 'members': [{'memberId': k, 'activity': v} for k, v in mems.items()]}
                    for app_id, mems in active_members.items()
                ],
                'calls_per_endpoint': [
                    {'applicationId': k[0], 'clubName': club_names.get(k[0], k[0]), 'path': k[1], 'count': v}
                    for k, v in calls_per_endpoint.items()
                ],
                'calls_per_member': [
                    {'applicationId': k[0], 'clubName': club_names.get(k[0], k[0]),
                     'memberId': k[1], 'memberName': member_names.get((k[0], k[1]), k[1]), 'count': v}
                    for k, v in calls_per_member.items()
                ],
                'timeframe': timeframe,
            })
        }

    except Exception as e:
        print(f"Error querying logs: {e}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}


def handle_timing(event, context):
    try:
        body = json.loads(event['body']) if isinstance(event.get('body'), str) else event.get('body', {})

        application_id = body.get('applicationId', '')
        member_id = body.get('memberId', '')
        phases = body.get('phases', {})
        total_ms = body.get('totalMs', 0)

        # Validate required fields
        if not application_id or not member_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'applicationId and memberId required'})
            }

        # Write structured log to CloudWatch
        print(json.dumps({
            "log_type": "startup_timing",
            "applicationId": application_id,
            "memberId": member_id,
            "firebase_ms": phases.get('firebase_ms', 0),
            "config_ms": phases.get('config_ms', 0),
            "first_frame_ms": phases.get('first_frame_ms', 0),
            "fetch_member_ms": phases.get('fetch_member_ms', 0),
            "get_customer_ms": phases.get('get_customer_ms', 0),
            "total_ms": total_ms,
            "timestamp": datetime.utcnow().isoformat()
        }))

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Startup timing recorded'})
        }
    except Exception as e:
        print(f"Error in handle_timing: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def _wait_for_query(logs, query_id):
    response = None
    for _ in range(10):
        response = logs.get_query_results(queryId=query_id)
        if response['status'] in ['Complete', 'Failed', 'Cancelled']:
            break
        time.sleep(0.5)
    return response


def handle_startup_stats(event, context):
    params = event.get('queryStringParameters') or {}
    timeframe = params.get('timeframe', 'day')

    logs = boto3.client('logs')
    log_group_name = os.environ.get('LAMBDA_LOG_GROUP_NAME') or context.log_group_name

    now = datetime.utcnow()
    if timeframe == 'minute':
        start_time = now - timedelta(minutes=1)
    elif timeframe == 'hour':
        start_time = now - timedelta(hours=1)
    elif timeframe == 'day':
        start_time = now - timedelta(days=1)
    elif timeframe == 'week':
        start_time = now - timedelta(weeks=1)
    else:
        start_time = now - timedelta(days=1)

    start_timestamp = int(start_time.timestamp())
    end_timestamp = int(now.timestamp())

    per_member_query = """
    fields memberId, applicationId, total_ms
    | filter log_type = "startup_timing"
    | stats pct(total_ms, 50) as p50, pct(total_ms, 95) as p95, pct(total_ms, 99) as p99, count() as count by memberId, applicationId
    """

    phase_query = """
    fields firebase_ms, config_ms, first_frame_ms, fetch_member_ms, get_customer_ms, total_ms
    | filter log_type = "startup_timing"
    | stats
        pct(firebase_ms, 50) as firebase_p50, pct(firebase_ms, 95) as firebase_p95, pct(firebase_ms, 99) as firebase_p99,
        pct(config_ms, 50) as config_p50, pct(config_ms, 95) as config_p95, pct(config_ms, 99) as config_p99,
        pct(first_frame_ms, 50) as first_frame_p50, pct(first_frame_ms, 95) as first_frame_p95, pct(first_frame_ms, 99) as first_frame_p99,
        pct(fetch_member_ms, 50) as fetch_member_p50, pct(fetch_member_ms, 95) as fetch_member_p95, pct(fetch_member_ms, 99) as fetch_member_p99,
        pct(get_customer_ms, 50) as get_customer_p50, pct(get_customer_ms, 95) as get_customer_p95, pct(get_customer_ms, 99) as get_customer_p99,
        pct(total_ms, 50) as total_p50, pct(total_ms, 95) as total_p95, pct(total_ms, 99) as total_p99,
        count() as count
    """

    try:
        per_member_id = logs.start_query(
            logGroupName=log_group_name,
            startTime=start_timestamp,
            endTime=end_timestamp,
            queryString=per_member_query,
            limit=1000
        )['queryId']

        phase_id = logs.start_query(
            logGroupName=log_group_name,
            startTime=start_timestamp,
            endTime=end_timestamp,
            queryString=phase_query,
            limit=1
        )['queryId']

        per_member_resp = _wait_for_query(logs, per_member_id)
        phase_resp = _wait_for_query(logs, phase_id)

        if per_member_resp['status'] != 'Complete':
            return {'statusCode': 500, 'body': json.dumps({'error': f'Per-member query failed: {per_member_resp["status"]}'})}
        if phase_resp['status'] != 'Complete':
            return {'statusCode': 500, 'body': json.dumps({'error': f'Phase query failed: {phase_resp["status"]}'})}

        startup_stats = []
        for row in per_member_resp['results']:
            stat = {}
            for item in row:
                field = item['field']
                value = item['value']
                if field in ['p50', 'p95', 'p99', 'count']:
                    try:
                        stat[field] = int(value) if value else 0
                    except:
                        stat[field] = value
                else:
                    stat[field] = value
            startup_stats.append(stat)

        app_ids = {s.get('applicationId', '') for s in startup_stats if s.get('applicationId')}
        club_names, member_names = _build_name_maps(app_ids)
        for stat in startup_stats:
            stat['clubName'] = club_names.get(stat.get('applicationId', ''), stat.get('applicationId', ''))
            stat['memberName'] = member_names.get(
                (stat.get('applicationId', ''), stat.get('memberId', '')),
                stat.get('memberId', '')
            )

        phase_stats = {}
        if phase_resp['results']:
            int_fields = {
                'firebase_p50', 'firebase_p95', 'firebase_p99',
                'config_p50', 'config_p95', 'config_p99',
                'first_frame_p50', 'first_frame_p95', 'first_frame_p99',
                'fetch_member_p50', 'fetch_member_p95', 'fetch_member_p99',
                'get_customer_p50', 'get_customer_p95', 'get_customer_p99',
                'total_p50', 'total_p95', 'total_p99', 'count',
            }
            for item in phase_resp['results'][0]:
                field = item['field']
                value = item['value']
                if field in int_fields:
                    try:
                        phase_stats[field] = int(value) if value else 0
                    except:
                        phase_stats[field] = value
                else:
                    phase_stats[field] = value

        return {
            'statusCode': 200,
            'body': json.dumps({
                'startup_stats': startup_stats,
                'phase_stats': phase_stats,
                'timeframe': timeframe
            })
        }
    except Exception as e:
        print(f"Error querying startup stats: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
