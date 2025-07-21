resource "aws_apigatewayv2_route" "photos_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /photos"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "photos_get_deep" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /photos/{proxy+}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "photos_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /photos"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
