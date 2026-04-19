resource "aws_apigatewayv2_route" "monitoring_stats_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /monitoring/stats"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "monitoring_startup_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /monitoring/startup"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "monitoring_timing_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /monitoring/timing"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
