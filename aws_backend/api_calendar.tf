resource "aws_apigatewayv2_route" "calendar_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /calendar"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
