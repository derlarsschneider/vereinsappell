resource "aws_dynamodb_table" "feedback_table" {
    name         = "${local.name_prefix}-feedback"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "applicationId"
    range_key    = "feedbackId"

    attribute {
        name = "applicationId"
        type = "S"
    }

    attribute {
        name = "feedbackId"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "feedback_get" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /feedback"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "feedback_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /feedback"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "feedback_reply_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /feedback/{feedbackId}/reply"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
