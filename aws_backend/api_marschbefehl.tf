resource "aws_dynamodb_table" "marschbefehl_table" {
    name         = "${local.name_prefix}-marschbefehl"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "applicationId"
    range_key    = "datetime"

    attribute {
        name = "applicationId"
        type = "S"
    }

    attribute {
        name = "datetime"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "marschbefehl_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /marschbefehl"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "marschbefehl_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /marschbefehl"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "marschbefehl_delete" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "DELETE /marschbefehl"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
