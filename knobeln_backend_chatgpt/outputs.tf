output "http_api_url" { value = aws_apigatewayv2_stage.http.default_route_settings[0].model_selection_expression != null ? aws_apigatewayv2_stage.http.invoke_url : aws_apigatewayv2_stage.http.invoke_url }
output "websocket_api_url" { value = aws_apigatewayv2_stage.ws.invoke_url }
output "dynamodb_table_name" { value = aws_dynamodb_table.knobeln.name }
output "scheduler_role_arn" { value = aws_iam_role.scheduler_invoke_role.arn }
