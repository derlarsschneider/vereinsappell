# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.environment}-${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for DynamoDB access
resource "aws_iam_policy" "dynamodb_access" {
  name        = "${var.environment}-${var.project_name}-dynamodb-access"
  description = "Policy for accessing Knobeln game tables"

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
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.knobeln_games.arn,
          "${aws_dynamodb_table.knobeln_games.arn}/index/*"
        ]
      }
    ]
  })
}

# Policy for EventBridge access
resource "aws_iam_policy" "eventbridge_access" {
  name        = "${var.environment}-${var.project_name}-eventbridge-access"
  description = "Policy for managing EventBridge rules"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:PutRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:DeleteRule",
          "events:DescribeRule",
          "events:EnableRule",
          "events:DisableRule"
        ]
        Resource = [
          "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${var.environment}-knobeln-*"
        ]
      }
    ]
  })
}

# Policy for API Gateway management
resource "aws_iam_policy" "api_gateway_management" {
  name        = "${var.environment}-${var.project_name}-apigw-management"
  description = "Policy for managing API Gateway connections"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = [
          "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.knobeln_ws.id}/*"
        ]
      }
    ]
  })
}

# Attach policies to the IAM role
resource "aws_iam_role_policy_attachment" "dynamodb_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

resource "aws_iam_role_policy_attachment" "eventbridge_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.eventbridge_access.arn
}

resource "aws_iam_role_policy_attachment" "api_gateway_management" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.api_gateway_management.arn
}
