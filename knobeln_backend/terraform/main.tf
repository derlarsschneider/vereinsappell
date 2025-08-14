terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

data "aws_caller_identity" "current" {}

# Enable DynamoDB point-in-time recovery
resource "aws_dynamodb_table" "knobeln_games" {
  name           = "${var.environment}-knobeln-games"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "game_id"
  range_key      = "sk"

  attribute {
    name = "game_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # GSI for querying active games
  global_secondary_index {
    name               = "StatusIndex"
    hash_key           = "status"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-knobeln-games"
    Environment = var.environment
  }
}

# API Gateway for HTTP and WebSocket APIs
resource "aws_apigatewayv2_api" "knobeln_http" {
  name          = "${var.environment}-knobeln-http"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://vereinsappell.web.app", "https://vereinsappell.derlarsschneider.de"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_api" "knobeln_ws" {
  name                       = "${var.environment}-knobeln-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}
