# aws_backend/backup.tf

# --- S3 Bucket ---

resource "aws_s3_bucket" "backup_bucket" {
    bucket = "vereinsappell-backups"
}

resource "aws_s3_bucket_public_access_block" "backup_bucket_public_access" {
    bucket                  = aws_s3_bucket.backup_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_bucket_lifecycle" {
    bucket = aws_s3_bucket.backup_bucket.id

    rule {
        id     = "delete-old-backups"
        status = "Enabled"

        filter {}

        expiration {
            days = 30
        }
    }
}

# --- backup-lambda IAM ---

resource "aws_iam_role" "backup_lambda_role" {
    name = "${local.name_prefix}-backup-lambda-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action    = "sts:AssumeRole"
            Effect    = "Allow"
            Principal = { Service = "lambda.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "backup_lambda_basic" {
    role       = aws_iam_role.backup_lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "backup_lambda_policy" {
    name = "${local.name_prefix}-backup-lambda-policy"
    role = aws_iam_role.backup_lambda_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = ["dynamodb:Scan", "dynamodb:GetItem"]
                Resource = [
                    aws_dynamodb_table.customer_config_table.arn,
                    aws_dynamodb_table.members_table.arn,
                    aws_dynamodb_table.marschbefehl_table.arn,
                    aws_dynamodb_table.fines_table.arn,
                ]
            },
            {
                Effect   = "Allow"
                Action   = ["s3:PutObject", "s3:ListBucket"]
                Resource = [
                    aws_s3_bucket.backup_bucket.arn,
                    "${aws_s3_bucket.backup_bucket.arn}/*",
                ]
            }
        ]
    })
}

# --- backup-lambda function ---

resource "aws_lambda_function" "backup_lambda" {
    function_name = "${local.name_prefix}-backup"
    role          = aws_iam_role.backup_lambda_role.arn
    handler       = "backup_handler.lambda_handler"
    runtime       = "python3.10"
    filename      = "lambda/backup/lambda.zip"
    timeout       = 300

    environment {
        variables = {
            BACKUP_BUCKET           = aws_s3_bucket.backup_bucket.bucket
            CUSTOMERS_TABLE_NAME    = aws_dynamodb_table.customer_config_table.name
            MEMBERS_TABLE_NAME      = aws_dynamodb_table.members_table.name
            MARSCHBEFEHL_TABLE_NAME = aws_dynamodb_table.marschbefehl_table.name
            FINES_TABLE_NAME        = aws_dynamodb_table.fines_table.name
        }
    }
}

resource "aws_lambda_permission" "backup_lambda_api" {
    statement_id  = "AllowAPIGatewayInvokeBackup"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.backup_lambda.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "backup_lambda_scheduler" {
    statement_id  = "AllowEventBridgeSchedulerInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.backup_lambda.function_name
    principal     = "scheduler.amazonaws.com"
    source_arn    = aws_scheduler_schedule.daily_backup.arn
}

# --- restore-lambda IAM ---

resource "aws_iam_role" "restore_lambda_role" {
    name = "${local.name_prefix}-restore-lambda-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action    = "sts:AssumeRole"
            Effect    = "Allow"
            Principal = { Service = "lambda.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "restore_lambda_basic" {
    role       = aws_iam_role.restore_lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "restore_lambda_policy" {
    name = "${local.name_prefix}-restore-lambda-policy"
    role = aws_iam_role.restore_lambda_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:Scan", "dynamodb:BatchWriteItem"]
                Resource = [
                    aws_dynamodb_table.customer_config_table.arn,
                    aws_dynamodb_table.members_table.arn,
                    aws_dynamodb_table.marschbefehl_table.arn,
                    aws_dynamodb_table.fines_table.arn,
                ]
            },
            {
                Effect   = "Allow"
                Action   = ["s3:GetObject", "s3:ListBucket"]
                Resource = [
                    aws_s3_bucket.backup_bucket.arn,
                    "${aws_s3_bucket.backup_bucket.arn}/*",
                ]
            }
        ]
    })
}

# --- restore-lambda function ---

resource "aws_lambda_function" "restore_lambda" {
    function_name = "${local.name_prefix}-restore"
    role          = aws_iam_role.restore_lambda_role.arn
    handler       = "restore_handler.lambda_handler"
    runtime       = "python3.10"
    filename      = "lambda/restore/lambda.zip"
    timeout       = 300

    environment {
        variables = {
            BACKUP_BUCKET           = aws_s3_bucket.backup_bucket.bucket
            CUSTOMERS_TABLE_NAME    = aws_dynamodb_table.customer_config_table.name
            MEMBERS_TABLE_NAME      = aws_dynamodb_table.members_table.name
            MARSCHBEFEHL_TABLE_NAME = aws_dynamodb_table.marschbefehl_table.name
            FINES_TABLE_NAME        = aws_dynamodb_table.fines_table.name
        }
    }
}

resource "aws_lambda_permission" "restore_lambda_api" {
    statement_id  = "AllowAPIGatewayInvokeRestore"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.restore_lambda.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- EventBridge Scheduler ---

resource "aws_iam_role" "scheduler_role" {
    name = "${local.name_prefix}-scheduler-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action    = "sts:AssumeRole"
            Effect    = "Allow"
            Principal = { Service = "scheduler.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy" "scheduler_policy" {
    name = "${local.name_prefix}-scheduler-policy"
    role = aws_iam_role.scheduler_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect   = "Allow"
            Action   = "lambda:InvokeFunction"
            Resource = aws_lambda_function.backup_lambda.arn
        }]
    })
}

resource "aws_scheduler_schedule" "daily_backup" {
    name       = "${local.name_prefix}-daily-backup"
    group_name = "default"

    flexible_time_window {
        mode = "OFF"
    }

    schedule_expression          = "cron(0 2 * * ? *)"
    schedule_expression_timezone = "Europe/Berlin"

    target {
        arn      = aws_lambda_function.backup_lambda.arn
        role_arn = aws_iam_role.scheduler_role.arn
        input    = jsonencode({ source = "aws.events" })
    }
}

# --- API Gateway integrations ---

resource "aws_apigatewayv2_integration" "backup_lambda_integration" {
    api_id                 = aws_apigatewayv2_api.http_api.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.backup_lambda.invoke_arn
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "restore_lambda_integration" {
    api_id                 = aws_apigatewayv2_api.http_api.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.restore_lambda.invoke_arn
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "admin_backup_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /admin/backup"
    target             = "integrations/${aws_apigatewayv2_integration.backup_lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "admin_backups_get" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /admin/backups"
    target             = "integrations/${aws_apigatewayv2_integration.backup_lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "admin_restore_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /admin/backup/{timestamp}/restore"
    target             = "integrations/${aws_apigatewayv2_integration.restore_lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "admin_table_clear" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "DELETE /admin/table/{tableName}/items"
    target             = "integrations/${aws_apigatewayv2_integration.restore_lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
