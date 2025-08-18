# main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "vereins-app-beta-"
  # name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"

  lambda_functions = {
    "game-handler"    = "./lambda/game-handler.zip"
    "websocket-handler" = "./lambda/websocket-handler.zip"
    "game-timer"     = "./lambda/game-timer.zip"
  }
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    AI          = "claude"
  }
}

# DynamoDB Tables
resource "aws_dynamodb_table" "knobeln_games" {
  name           = "${local.name_prefix}-games"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "gameId"

  attribute {
    name = "gameId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name     = "StatusIndex"
    hash_key = "status"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table" "websocket_connections" {
  name           = "${local.name_prefix}-connections"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  attribute {
    name = "gameId"
    type = "S"
  }

  global_secondary_index {
    name     = "GameIdIndex"
    hash_key = "gameId"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = local.common_tags
}

# API Gateway HTTP API
data "aws_apigatewayv2_api" "http_api" {
  api_id = "v49kyt4758"
}

data "aws_iam_role" "lambda_role" {
  name = "vereins-app-beta-lambda_role"
}

# API Gateway WebSocket API
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = "${local.name_prefix}-websocket-api"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = local.common_tags
}

# IAM Policies for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = data.aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.name_prefix}-lambda-dynamodb-policy"
  role = data.aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.knobeln_games.arn,
          aws_dynamodb_table.websocket_connections.arn,
          "${aws_dynamodb_table.knobeln_games.arn}/index/*",
          "${aws_dynamodb_table.websocket_connections.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "scheduler:CreateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Functions
resource "aws_lambda_function" "game_handler" {
  filename         = "lambda/game-handler.zip"
  function_name    = "${local.name_prefix}-game-handler"
  role            = data.aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      GAMES_TABLE_NAME       = aws_dynamodb_table.knobeln_games.name
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_stage.websocket_stage.invoke_url
      TIMER_LAMBDA_ARN       = aws_lambda_function.game_timer.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.game_handler_logs,
  ]

  tags = local.common_tags
}

resource "aws_lambda_function" "websocket_handler" {
  filename         = "lambda/websocket-handler.zip"
  function_name    = "${local.name_prefix}-websocket-handler"
  role            = data.aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      GAMES_TABLE_NAME       = aws_dynamodb_table.knobeln_games.name
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.websocket_handler_logs,
  ]

  tags = local.common_tags
}

resource "aws_lambda_function" "game_timer" {
  filename         = "lambda/game-timer.zip"
  function_name    = "${local.name_prefix}-game-timer"
  role            = data.aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      GAMES_TABLE_NAME       = aws_dynamodb_table.knobeln_games.name
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_stage.websocket_stage.invoke_url
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.game_timer_logs,
  ]

  tags = local.common_tags
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "game_handler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-game-handler"
  retention_in_days = 14
  tags             = local.common_tags
}

resource "aws_cloudwatch_log_group" "websocket_handler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-websocket-handler"
  retention_in_days = 14
  tags             = local.common_tags
}

resource "aws_cloudwatch_log_group" "game_timer_logs" {
  name              = "/aws/lambda/${local.name_prefix}-game-timer"
  retention_in_days = 14
  tags             = local.common_tags
}

# HTTP API Routes
resource "aws_apigatewayv2_integration" "game_handler_integration" {
  api_id             = data.aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.game_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "create_game" {
  api_id    = data.aws_apigatewayv2_api.http_api.id
  route_key = "POST /games"
  target    = "integrations/${aws_apigatewayv2_integration.game_handler_integration.id}"
}

resource "aws_apigatewayv2_route" "join_game" {
  api_id    = data.aws_apigatewayv2_api.http_api.id
  route_key = "POST /games/{gameId}/join"
  target    = "integrations/${aws_apigatewayv2_integration.game_handler_integration.id}"
}

resource "aws_apigatewayv2_route" "pick_sticks" {
  api_id    = data.aws_apigatewayv2_api.http_api.id
  route_key = "POST /games/{gameId}/pick"
  target    = "integrations/${aws_apigatewayv2_integration.game_handler_integration.id}"
}

resource "aws_apigatewayv2_route" "make_guess" {
  api_id    = data.aws_apigatewayv2_api.http_api.id
  route_key = "POST /games/{gameId}/guess"
  target    = "integrations/${aws_apigatewayv2_integration.game_handler_integration.id}"
}

resource "aws_apigatewayv2_route" "get_game" {
  api_id    = data.aws_apigatewayv2_api.http_api.id
  route_key = "GET /games/{gameId}"
  target    = "integrations/${aws_apigatewayv2_integration.game_handler_integration.id}"
}

# HTTP API Stage
resource "aws_apigatewayv2_stage" "http_stage" {
  api_id      = data.aws_apigatewayv2_api.http_api.id
  name        = var.environment
  auto_deploy = true

  tags = local.common_tags
}

# WebSocket API Integration
resource "aws_apigatewayv2_integration" "websocket_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_handler.invoke_arn
}

# WebSocket Routes
resource "aws_apigatewayv2_route" "websocket_connect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_integration.id}"
}

resource "aws_apigatewayv2_route" "websocket_disconnect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_integration.id}"
}

resource "aws_apigatewayv2_route" "websocket_default" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_integration.id}"
}

# WebSocket Stage
resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id      = aws_apigatewayv2_api.websocket_api.id
  name        = var.environment
  auto_deploy = true

  tags = local.common_tags
}

# Lambda Permissions
resource "aws_lambda_permission" "allow_api_gateway_http" {
  statement_id  = "AllowExecutionFromAPIGatewayHTTP"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.game_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_websocket" {
  statement_id  = "AllowExecutionFromAPIGatewayWebSocket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.game_timer.function_name
  principal     = "events.amazonaws.com"
}

# EventBridge Scheduler Role
resource "aws_iam_role" "scheduler_role" {
  name = "${local.name_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler_lambda_policy" {
  name = "${local.name_prefix}-scheduler-lambda-policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.game_timer.arn
      }
    ]
  })
}

# Outputs
output "http_api_url" {
  description = "HTTP API Gateway URL"
  value       = aws_apigatewayv2_stage.http_stage.invoke_url
}

output "websocket_api_url" {
  description = "WebSocket API Gateway URL"
  value       = aws_apigatewayv2_stage.websocket_stage.invoke_url
}

output "games_table_name" {
  description = "DynamoDB Games Table Name"
  value       = aws_dynamodb_table.knobeln_games.name
}

output "connections_table_name" {
  description = "DynamoDB Connections Table Name"
  value       = aws_dynamodb_table.websocket_connections.name
}

output "game_handler_function_name" {
  description = "Game Handler Lambda Function Name"
  value       = aws_lambda_function.game_handler.function_name
}

output "websocket_handler_function_name" {
  description = "WebSocket Handler Lambda Function Name"
  value       = aws_lambda_function.websocket_handler.function_name
}

output "game_timer_function_name" {
  description = "Game Timer Lambda Function Name"
  value       = aws_lambda_function.game_timer.function_name
}

output "scheduler_role_arn" {
  description = "EventBridge Scheduler Role ARN"
  value       = aws_iam_role.scheduler_role.arn
}

output "deployment_info" {
  description = "Deployment Information"
  value = {
    project_name = var.project_name
    environment  = var.environment
    region      = var.aws_region
    deployed_at = timestamp()
  }
}

# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "knobeln"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins for HTTP API"
  type        = list(string)
  default     = ["*"]
}
