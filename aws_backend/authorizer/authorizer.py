import boto3


def lambda_authorizer(event, context):
    headers = event.get("headers", {})
    application_id = headers.get("applicationId") or headers.get("applicationid", "")
    print("Received application id:", application_id)
    # check DynamoDB for registered clients
    if application_id in get_application_ids():
        return {
            "isAuthorized": True
        }
    else:
        return {
            "isAuthorized": False
        }


def get_application_ids():
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('vereinsappell-customers')
    response = table.scan()
    application_ids = [item['application_id'] for item in response['Items']]
    return application_ids
