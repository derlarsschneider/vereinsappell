resource "aws_dynamodb_table" "news_table" {
    name         = "${local.name_prefix}-news"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "newsId"

    attribute {
        name = "newsId"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "news_get" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /news"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "news_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /news"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "news_delete" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "DELETE /news/{newsId}"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
