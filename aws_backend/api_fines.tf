resource "aws_dynamodb_table" "fines_table" {
    name         = "${local.name_prefix}-fines"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "memberId"
    range_key    = "fineId"

    attribute {
        name = "fineId"
        type = "S"
    }
    attribute {
        name = "memberId"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "fines_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /fines"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "fines_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /fines"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "fines_delete" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "DELETE /fines/{fineId}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
