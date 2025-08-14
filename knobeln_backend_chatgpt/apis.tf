# HTTP API
resource "aws_apigatewayv2_api" "http" {
    name          = local.http_api_name
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "http" {
    api_id      = aws_apigatewayv2_api.http.id
    name        = "$default"
    auto_deploy = true
}

# WebSocket API
resource "aws_apigatewayv2_api" "ws" {
    name                       = local.ws_api_name
    protocol_type              = "WEBSOCKET"
    route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_integration" "ws_connect" {
    api_id                 = aws_apigatewayv2_api.ws.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.ws_on_connect.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "ws_disconnect" {
    api_id                 = aws_apigatewayv2_api.ws.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.ws_on_disconnect.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "ws_default" {
    api_id                 = aws_apigatewayv2_api.ws.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.ws_broadcast.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ws_connect" {
    api_id    = aws_apigatewayv2_api.ws.id
    route_key = "$connect"
    target    = "integrations/${aws_apigatewayv2_integration.ws_connect.id}"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
    api_id    = aws_apigatewayv2_api.ws.id
    route_key = "$disconnect"
    target    = "integrations/${aws_apigatewayv2_integration.ws_disconnect.id}"
}

resource "aws_apigatewayv2_route" "ws_default" {
    api_id    = aws_apigatewayv2_api.ws.id
    route_key = "$default"
    target    = "integrations/${aws_apigatewayv2_integration.ws_default.id}"
}

resource "aws_apigatewayv2_stage" "ws" {
    api_id      = aws_apigatewayv2_api.ws.id
    name        = "$default"
    auto_deploy = true
}

# Lambda permissions for API Gateway invocations
resource "aws_lambda_permission" "ws_on_connect_invoke" {
    statement_id  = "AllowAPIGatewayInvokeWSConnect"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.ws_on_connect.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.ws.execution_arn}/*/$connect"
}

resource "aws_lambda_permission" "ws_on_disconnect_invoke" {
    statement_id  = "AllowAPIGatewayInvokeWSDisconnect"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.ws_on_disconnect.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.ws.execution_arn}/*/$disconnect"
}

resource "aws_lambda_permission" "ws_default_invoke" {
    statement_id  = "AllowAPIGatewayInvokeWSDefault"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.ws_broadcast.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.ws.execution_arn}/*/$default"
}

# HTTP integrations & routes
resource "aws_apigatewayv2_integration" "http_create_game" {
    api_id                 = aws_apigatewayv2_api.http.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.http_create_game.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "http_post_games" {
    api_id    = aws_apigatewayv2_api.http.id
    route_key = "POST /games"
    target    = "integrations/${aws_apigatewayv2_integration.http_create_game.id}"
}

resource "aws_lambda_permission" "http_create_game_invoke" {
    statement_id  = "AllowInvokeCreateGame"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.http_create_game.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/games"
}

resource "aws_apigatewayv2_integration" "http_join" {
    api_id                 = aws_apigatewayv2_api.http.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.http_join_game.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "http_post_join" {
    api_id    = aws_apigatewayv2_api.http.id
    route_key = "POST /games/{id}/join"
    target    = "integrations/${aws_apigatewayv2_integration.http_join.id}"
}

resource "aws_lambda_permission" "http_join_invoke" {
    statement_id  = "AllowInvokeJoin"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.http_join_game.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/games/*/join"
}

resource "aws_apigatewayv2_integration" "http_pick" {
    api_id                 = aws_apigatewayv2_api.http.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.http_pick.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "http_post_pick" {
    api_id    = aws_apigatewayv2_api.http.id
    route_key = "POST /games/{id}/pick"
    target    = "integrations/${aws_apigatewayv2_integration.http_pick.id}"
}

resource "aws_lambda_permission" "http_pick_invoke" {
    statement_id  = "AllowInvokePick"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.http_pick.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/games/*/pick"
}

resource "aws_apigatewayv2_integration" "http_guess" {
    api_id                 = aws_apigatewayv2_api.http.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.http_guess.invoke_arn
    integration_method     = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "http_post_guess" {
    api_id    = aws_apigatewayv2_api.http.id
    route_key = "POST /games/{id}/guess"
    target    = "integrations/${aws_apigatewayv2_integration.http_guess.id}"
}

resource "aws_lambda_permission" "http_guess_invoke" {
    statement_id  = "AllowInvokeGuess"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.http_guess.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/games/*/guess"
}

resource "aws_apigatewayv2_integration" "http_get_state" {
    api_id                 = aws_apigatewayv2_api.http.id
    integration_type       = "AWS_PROXY"
    integration_uri        = aws_lambda_function.http_get_state.invoke_arn
    integration_method     = "GET"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "http_get_state" {
    api_id    = aws_apigatewayv2_api.http.id
    route_key = "GET /games/current"
    target    = "integrations/${aws_apigatewayv2_integration.http_get_state.id}"
}

resource "aws_lambda_permission" "http_get_state_invoke" {
    statement_id  = "AllowInvokeGetState"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.http_get_state.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*/games/current"
}
