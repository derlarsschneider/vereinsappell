import boto3
import json
import os
import time
from datetime import datetime, timedelta

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
    fields applicationId, memberId, @timestamp
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
        
        for row in results:
            app_id = next((item['value'] for item in row if item['field'] == 'applicationId'), 'unknown')
            mem_id = next((item['value'] for item in row if item['field'] == 'memberId'), 'unknown')
            
            # Aggregate calls per club
            calls_per_club[app_id] = calls_per_club.get(app_id, 0) + 1
            
            # Aggregate member activity
            if app_id not in active_members:
                active_members[app_id] = {}
            active_members[app_id][mem_id] = active_members[app_id].get(mem_id, 0) + 1

        return {
            'statusCode': 200,
            'body': json.dumps({
                'calls_per_club': [{'applicationId': k, 'count': v} for k, v in calls_per_club.items()],
                'active_members': [
                    {
                        'applicationId': app_id, 
                        'members': [{'memberId': k, 'activity': v} for k, v in mems.items()]
                    } 
                    for app_id, mems in active_members.items()
                ],
                'timeframe': timeframe
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

    start_timestamp = int(start_time.timestamp() * 1000)
    end_timestamp = int(now.timestamp() * 1000)

    query = """
    fields memberId, applicationId, total_ms
    | filter log_type = "startup_timing"
    | stats pct(total_ms, 50) as p50, pct(total_ms, 95) as p95, pct(total_ms, 99) as p99, count() as count by memberId, applicationId
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
        response = None

        for _ in range(10):
            response = logs.get_query_results(queryId=query_id)
            if response['status'] in ['Complete', 'Failed', 'Cancelled']:
                break
            time.sleep(0.5)

        if response['status'] != 'Complete':
            return {
                'statusCode': 500,
                'body': json.dumps({'error': f'Query failed: {response["status"]}'})
            }

        startup_stats = []
        for row in response['results']:
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

        return {
            'statusCode': 200,
            'body': json.dumps({
                'startup_stats': startup_stats,
                'timeframe': timeframe
            })
        }
    except Exception as e:
        print(f"Error querying startup stats: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
