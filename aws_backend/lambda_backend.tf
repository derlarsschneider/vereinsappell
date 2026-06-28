resource "aws_lambda_function" "lambda_backend" {
    function_name = "${local.name_prefix}-lambda_backend"
    role          = aws_iam_role.lambda_role.arn
    handler       = "lambda_handler.lambda_handler"
    runtime       = "python3.10"
    filename      = "lambda/lambda.zip"
    publish       = true

    environment {
        variables = {
            ERROR_TABLE_NAME = aws_dynamodb_table.error_table.name,
            CUSTOMERS_TABLE_NAME = aws_dynamodb_table.customer_config_table.name,
            FINES_TABLE_NAME = aws_dynamodb_table.fines_table.name,
            MEMBERS_TABLE_NAME = aws_dynamodb_table.members_table.name,
            MARSCHBEFEHL_TABLE_NAME = aws_dynamodb_table.marschbefehl_table.name,
            S3_BUCKET_NAME = aws_s3_bucket.s3_bucket.bucket,
            API_BASE_URL             = aws_apigatewayv2_api.http_api.api_endpoint,
            LAMBDA_LOG_GROUP_NAME    = "/aws/lambda/${local.name_prefix}-lambda_backend",
            PERF_LOGGING_ENABLED     = "true",
            CONTACT_EMAIL            = "info@vereinsappell.de",
        }
    }
}

# prod alias points to a specific published version — managed by promote.sh, not Terraform
resource "aws_lambda_alias" "prod" {
    name          = "prod"
    function_name = aws_lambda_function.lambda_backend.function_name
    # Bootstrapped to the first Terraform-published version; promote.sh owns it after that
    function_version = aws_lambda_function.lambda_backend.version

    lifecycle {
        ignore_changes = [function_version]
    }
}

# dev alias always tracks $LATEST
resource "aws_lambda_alias" "dev" {
    name             = "dev"
    function_name    = aws_lambda_function.lambda_backend.function_name
    function_version = "$LATEST"
}

resource "aws_dynamodb_table" "error_table" {
    name         = "${local.name_prefix}-error"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "id"

    attribute {
        name = "id"
        type = "S"
    }
}

resource "aws_lambda_permission" "api_gateway_prod" {
    statement_id  = "AllowAPIGatewayInvokeProd"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_backend.function_name
    qualifier     = aws_lambda_alias.prod.name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_dev" {
    statement_id  = "AllowAPIGatewayInvokeDev"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_backend.function_name
    qualifier     = aws_lambda_alias.dev.name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_api" "http_api" {
    name          = "${local.name_prefix}-api"
    protocol_type = "HTTP"

    cors_configuration {
        allow_origins     = ["*"]
        allow_methods     = ["GET", "POST", "DELETE", "OPTIONS", "PUT"]
        allow_headers     = ["content-type", "applicationId", "memberId", "password"]
        allow_credentials = false
        max_age           = 3600
    }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id                 = aws_apigatewayv2_api.http_api.id
    integration_type       = "AWS_PROXY"
    integration_uri        = "arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_backend.arn}:$${stageVariables.alias}/invocations"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "default" {
    api_id      = aws_apigatewayv2_api.http_api.id
    name        = "$default"
    auto_deploy = true

    stage_variables = {
        alias = "prod"
    }

    default_route_settings {
        throttling_rate_limit  = 50
        throttling_burst_limit = 100
    }
}

resource "aws_apigatewayv2_stage" "dev" {
    api_id      = aws_apigatewayv2_api.http_api.id
    name        = "dev"
    auto_deploy = true

    stage_variables = {
        alias = "dev"
    }

    default_route_settings {
        throttling_rate_limit  = 10
        throttling_burst_limit = 20
    }
}
