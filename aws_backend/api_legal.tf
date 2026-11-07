resource "aws_dynamodb_table" "legal_texts_table" {
    name         = "${local.name_prefix}-legal-texts"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "id"

    attribute {
        name = "id"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "legal_get" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /legal"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "legal_put" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "PUT /legal"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
