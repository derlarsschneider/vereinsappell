resource "aws_apigatewayv2_route" "docs_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /docs"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "doc_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /docs/{fileName}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "docs_delete" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "DELETE /docs/{fileName}"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}

resource "aws_apigatewayv2_route" "docs_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /docs"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "CUSTOM"
    authorizer_id      = aws_apigatewayv2_authorizer.lambda_authorizer.id
}
