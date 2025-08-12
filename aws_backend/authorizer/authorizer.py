import boto3

def lambda_authorizer(event, context):
    headers = event.get("headers", {})
    application_id = headers.get("applicationid", "")
    member_id = headers.get("memberid", "")
    # check DynamoDB for registered clients
    if application_id in get_application_ids():
        return {
            "isAuthorized": True,
            # "context": {
            #     "user": "trusted-client"
            # }
        }
    else:
        return {
            "isAuthorized": False,
            # "context": {},
            # "headers": {
            #     "Access-Control-Allow-Origin": "https://vereinsappell.web.app",
            #     "Access-Control-Allow-Headers": "applicationId,content-type",
            #     "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS"
            # }
        }


def get_application_ids():
    # print("get_application_ids")
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('vereinsappell-customers')
    response = table.scan()
    application_ids = [item['application_id'] for item in response['Items']]
    # print("application_ids:", application_ids)
    return application_ids
