resource "aws_dynamodb_table" "customer_config_table" {
    name         = "vereinsappell-customers"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "application_id"

    attribute {
        name = "application_id"
        type = "S"
    }
}

resource "aws_apigatewayv2_route" "customer_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /customers/{customerId}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "customer_list" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "GET /customers"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "customer_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /customers"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "customer_put" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "PUT /customers/{customerId}"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
