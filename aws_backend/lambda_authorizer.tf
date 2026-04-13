resource "aws_lambda_function" "lambda_authorizer" {
    function_name = "${local.name_prefix}-lambda_authorizer"
    role          = aws_iam_role.lambda_role.arn
    handler       = "authorizer.lambda_authorizer"
    runtime       = "python3.10"
    filename      = "authorizer/lambda.zip"
}

# Berechtigung: API Gateway darf Authorizer aufrufen
resource "aws_lambda_permission" "auth_api_permission" {
    statement_id  = "AllowExecutionFromAPIGatewayAuthorizer"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_authorizer.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Lambda Authorizer
resource "aws_apigatewayv2_authorizer" "lambda_authorizer" {
    name                              = "${local.name_prefix}-lambda_authorizer"
    api_id                            = aws_apigatewayv2_api.http_api.id
    authorizer_type                   = "REQUEST"
    authorizer_uri                    = aws_lambda_function.lambda_authorizer.invoke_arn
    identity_sources                  = ["$request.header.applicationId", "$request.header.memberId"]
    authorizer_payload_format_version = "2.0"
    enable_simple_responses           = true
    authorizer_result_ttl_in_seconds  = 300
}
