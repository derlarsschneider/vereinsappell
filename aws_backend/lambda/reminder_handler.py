from api_reminders import check_reminders


def lambda_handler(event, context):
    return check_reminders(event, context)
