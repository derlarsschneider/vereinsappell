resource "aws_lambda_function" "lambda_backend" {
    function_name = "${local.name_prefix}-lambda_backend"
    role          = aws_iam_role.lambda_role.arn
    handler       = "lambda_handler.lambda_handler"
    runtime       = "python3.10"
    filename      = "lambda/lambda.zip"

    environment {
        variables = {
            FINES_TABLE_NAME = aws_dynamodb_table.fines_table.name,
            MEMBERS_TABLE_NAME = aws_dynamodb_table.members_table.name,
            MARSCHBEFEHL_TABLE_NAME = aws_dynamodb_table.marschbefehl_table.name,
            S3_BUCKET_NAME = aws_s3_bucket.s3_bucket.bucket,
        }
    }
}

resource "aws_lambda_permission" "api_gateway" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_backend.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_api" "http_api" {
    name          = "${local.name_prefix}-api"
    protocol_type = "HTTP"

    cors_configuration {
        allow_origins     = [
            "https://vereinsappell.web.app",
            "http://127.0.0.1:8080",
            "http://localhost:8080"
        ]
        allow_methods     = ["GET", "POST", "DELETE", "OPTIONS"]
        allow_headers     = ["content-type"]
        allow_credentials = false
        max_age           = 3600
    }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id                 = aws_apigatewayv2_api.http_api.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.lambda_backend.invoke_arn
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "default" {
    api_id      = aws_apigatewayv2_api.http_api.id
    name        = "$default"
    auto_deploy = true
}
