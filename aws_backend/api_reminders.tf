# DynamoDB table for deduplication
resource "aws_dynamodb_table" "reminders_sent_table" {
  name         = "${local.name_prefix}-reminders_sent"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "applicationId"
  range_key    = "memberId_eventId"

  attribute {
    name = "applicationId"
    type = "S"
  }
  attribute {
    name = "memberId_eventId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# Lambda function for reminders
resource "aws_lambda_function" "lambda_reminders" {
  function_name = "${local.name_prefix}-lambda_reminders"
  role          = aws_iam_role.lambda_role.arn
  handler       = "reminder_handler.lambda_handler"
  runtime       = "python3.10"
  filename      = "lambda/lambda.zip"
  timeout       = 300

  environment {
    variables = {
      MEMBERS_TABLE_NAME    = aws_dynamodb_table.members_table.name
      REMINDERS_TABLE_NAME  = aws_dynamodb_table.reminders_sent_table.name
      CUSTOMERS_TABLE_NAME  = aws_dynamodb_table.customer_config_table.name
      S3_BUCKET_NAME        = aws_s3_bucket.s3_bucket.bucket
      FIREBASE_SECRET_NAME  = aws_secretsmanager_secret.firebase_credentials.name
    }
  }
}

# EventBridge rule – every hour
resource "aws_cloudwatch_event_rule" "reminders_hourly" {
  name                = "${local.name_prefix}-reminders-hourly"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "reminders_target" {
  rule      = aws_cloudwatch_event_rule.reminders_hourly.name
  target_id = "lambda_reminders"
  arn       = aws_lambda_function.lambda_reminders.arn
}

resource "aws_lambda_permission" "eventbridge_reminders" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_reminders.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reminders_hourly.arn
}
