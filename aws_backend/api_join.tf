resource "aws_apigatewayv2_route" "join_club_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /join/club"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_club_options" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "OPTIONS /join/club"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_member_post" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "POST /join/member"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "join_member_options" {
    api_id             = aws_apigatewayv2_api.http_api.id
    route_key          = "OPTIONS /join/member"
    target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
    authorization_type = "NONE"
}
