def lambda_authorizer(event, context):
    headers = event.get("headers", {})
    application_id = headers.get("applicationId") or headers.get("applicationid", "")
    print("Received application id:", application_id)
    # check DynamoDB for registered clients
    if application_id == "sad":
        return {
            "isAuthorized": True
        }
    else:
        return {
            "isAuthorized": False
        }
