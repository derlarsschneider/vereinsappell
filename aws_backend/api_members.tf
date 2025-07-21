resource "aws_dynamodb_table" "members_table" {
    name         = "${local.name_prefix}-members"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "memberId"

    attribute {
        name = "memberId"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "members_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /members"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "member_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /members/{memberId}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "members_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /members"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "members_delete" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "DELETE /members/{memberId}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
