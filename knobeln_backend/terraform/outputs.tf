output "http_api_endpoint" {
  description = "HTTP API endpoint URL"
  value       = aws_apigatewayv2_api.knobeln_http.api_endpoint
}

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint URL"
  value       = aws_apigatewayv2_api.knobeln_ws.api_endpoint
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.knobeln_games.name
}

output "lambda_functions" {
  description = "Map of Lambda function names to their ARNs"
  value       = {
    for k, v in aws_lambda_function.this : k => v.arn
  }
}

output "api_gateway_id" {
  description = "HTTP API Gateway ID"
  value       = aws_apigatewayv2_api.knobeln_http.id
}

output "websocket_gateway_id" {
  description = "WebSocket API Gateway ID"
  value       = aws_apigatewayv2_api.knobeln_ws.id
}

output "api_gateway_execution_arn" {
  description = "HTTP API Gateway execution ARN"
  value       = aws_apigatewayv2_api.knobeln_http.execution_arn
}
