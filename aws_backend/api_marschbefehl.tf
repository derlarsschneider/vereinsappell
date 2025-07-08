resource "aws_dynamodb_table" "marschbefehl_table" {
    name         = "${local.name_prefix}-marschbefehl"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "type"
    range_key    = "datetime"

    attribute {
        name = "type"
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
}
