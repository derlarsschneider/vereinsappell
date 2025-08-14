# HTTP API Gateway Stage
resource "aws_apigatewayv2_stage" "http_stage" {
  api_id      = aws_apigatewayv2_api.knobeln_http.id
  name        = "$default"
  auto_deploy = true
  
  default_route_settings {
    detailed_metrics_enabled = true
    throttling_rate_limit   = 100
    throttling_burst_limit  = 50
  }
  
  # Enable CloudWatch logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.http_api.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

# CloudWatch Log Group for HTTP API
resource "aws_cloudwatch_log_group" "http_api" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.knobeln_http.name}"
  retention_in_days = 14
}

# API Gateway authorizer (JWT)
resource "aws_apigatewayv2_authorizer" "http_authorizer" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.environment}-knobeln-http-authorizer"
  
  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# API Gateway integrations for each endpoint
# Create Game
resource "aws_apigatewayv2_integration" "create_game" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.create_game.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_game" {
  api_id    = aws_apigatewayv2_api.knobeln_http.id
  route_key = "POST /games"
  target    = "integrations/${aws_apigatewayv2_integration.create_game.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.http_authorizer.id
}

# Join Game
resource "aws_apigatewayv2_integration" "join_game" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.join_game.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "join_game" {
  api_id    = aws_apigatewayv2_api.knobeln_http.id
  route_key = "POST /games/{gameId}/join"
  target    = "integrations/${aws_apigatewayv2_integration.join_game.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.http_authorizer.id
}

# Pick Sticks
resource "aws_apigatewayv2_integration" "pick_sticks" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.pick_sticks.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "pick_sticks" {
  api_id    = aws_apigatewayv2_api.knobeln_http.id
  route_key = "POST /games/{gameId}/pick"
  target    = "integrations/${aws_apigatewayv2_integration.pick_sticks.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.http_authorizer.id
}

# Guess Total
resource "aws_apigatewayv2_integration" "guess_total" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.guess_total.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "guess_total" {
  api_id    = aws_apigatewayv2_api.knobeln_http.id
  route_key = "POST /games/{gameId}/guess"
  target    = "integrations/${aws_apigatewayv2_integration.guess_total.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.http_authorizer.id
}

# Get Game Status
resource "aws_apigatewayv2_integration" "get_game" {
  api_id           = aws_apigatewayv2_api.knobeln_http.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.get_game.invoke_arn
  integration_method = "GET"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_game" {
  api_id    = aws_apigatewayv2_api.knobeln_http.id
  route_key = "GET /games/{gameId}"
  target    = "integrations/${aws_apigatewayv2_integration.get_game.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.http_authorizer.id
}

# Lambda permissions for HTTP API
resource "aws_lambda_permission" "create_game" {
  statement_id  = "AllowExecutionFromAPIGateway_CreateGame"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_game.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "join_game" {
  statement_id  = "AllowExecutionFromAPIGateway_JoinGame"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.join_game.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "pick_sticks" {
  statement_id  = "AllowExecutionFromAPIGateway_PickSticks"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pick_sticks.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "guess_total" {
  statement_id  = "AllowExecutionFromAPIGateway_GuessTotal"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guess_total.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_game" {
  statement_id  = "AllowExecutionFromAPIGateway_GetGame"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_game.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_http.execution_arn}/*/*"
}
