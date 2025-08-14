# WebSocket API Gateway Stage
resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id      = aws_apigatewayv2_api.knobeln_ws.id
  name        = "$default"
  auto_deploy = true
  
  default_route_settings {
    detailed_metrics_enabled = true
    throttling_rate_limit   = 100
    throttling_burst_limit  = 50
  }
  
  # Enable CloudWatch logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.websocket_api.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

# CloudWatch Log Group for WebSocket API
resource "aws_cloudwatch_log_group" "websocket_api" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.knobeln_ws.name}"
  retention_in_days = 14
}

# WebSocket API Route: $connect
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.knobeln_ws.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_connect.id}"
}

resource "aws_apigatewayv2_integration" "websocket_connect" {
  api_id           = aws_apigatewayv2_api.knobeln_ws.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.websocket_handler.invoke_arn
  integration_method = "POST"
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# WebSocket API Route: $disconnect
resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.knobeln_ws.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_disconnect.id}"
}

resource "aws_apigatewayv2_integration" "websocket_disconnect" {
  api_id           = aws_apigatewayv2_api.knobeln_ws.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.websocket_handler.invoke_arn
  integration_method = "POST"
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# WebSocket API Route: $default
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.knobeln_ws.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_default.id}"
}

resource "aws_apigatewayv2_integration" "websocket_default" {
  api_id           = aws_apigatewayv2_api.knobeln_ws.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.websocket_handler.invoke_arn
  integration_method = "POST"
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# Custom WebSocket Routes
resource "aws_apigatewayv2_route" "send_message" {
  api_id    = aws_apigatewayv2_api.knobeln_ws.id
  route_key = "sendmessage"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_send_message.id}"
}

resource "aws_apigatewayv2_integration" "websocket_send_message" {
  api_id           = aws_apigatewayv2_api.knobeln_ws.id
  integration_type = "AWS_PROXY"
  
  integration_uri    = aws_lambda_function.websocket_handler.invoke_arn
  integration_method = "POST"
  content_handling_strategy = "CONVERT_TO_TEXT"
}

# WebSocket API Deployment
resource "aws_apigatewayv2_deployment" "websocket" {
  api_id      = aws_apigatewayv2_api.knobeln_ws.id
  description = "WebSocket API deployment"
  
  depends_on = [
    aws_apigatewayv2_route.connect,
    aws_apigatewayv2_route.disconnect,
    aws_apigatewayv2_route.default,
    aws_apigatewayv2_route.send_message
  ]
  
  lifecycle {
    create_before_destroy = true
  }
}

# Lambda permissions for WebSocket API
resource "aws_lambda_permission" "websocket_connect" {
  statement_id  = "AllowExecutionFromAPIGateway_connect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_ws.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_disconnect" {
  statement_id  = "AllowExecutionFromAPIGateway_disconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_ws.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_default" {
  statement_id  = "AllowExecutionFromAPIGateway_default"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_ws.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_send_message" {
  statement_id  = "AllowExecutionFromAPIGateway_sendmessage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.knobeln_ws.execution_arn}/*/*"
}
