locals {
  lambda_source_dir = "${path.module}/../src"
  lambda_zip_dir   = "${path.module}/../.terraform/lambda_zips"
}

# Create directory for Lambda zip files
resource "null_resource" "create_lambda_zip_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.lambda_zip_dir}"
  }
}

# Common environment variables for all Lambda functions
locals {
  common_env_vars = {
    DYNAMODB_TABLE = aws_dynamodb_table.knobeln_games.name
    WEBSOCKET_API  = aws_apigatewayv2_api.knobeln_ws.api_endpoint
    STAGE          = var.environment
  }
}

# Lambda function for creating a new game
resource "aws_lambda_function" "create_game" {
  function_name = "${var.environment}-${var.project_name}-create-game"
  handler      = "create_game.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/create_game.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/create_game.py")

  environment {
    variables = merge(local.common_env_vars, {
      GAME_START_DELAY = var.game_start_delay_seconds
    })
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.eventbridge_access
  ]
}

# Lambda function for joining a game
resource "aws_lambda_function" "join_game" {
  function_name = "${var.environment}-${var.project_name}-join-game"
  handler      = "join_game.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/join_game.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/join_game.py")

  environment {
    variables = local.common_env_vars
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.api_gateway_management
  ]
}

# Lambda function for picking sticks
resource "aws_lambda_function" "pick_sticks" {
  function_name = "${var.environment}-${var.project_name}-pick-sticks"
  handler      = "pick_sticks.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/pick_sticks.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/pick_sticks.py")

  environment {
    variables = merge(local.common_env_vars, {
      PICK_TIMEOUT = var.pick_timeout_seconds
    })
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.eventbridge_access
  ]
}

# Lambda function for guessing the total number of sticks
resource "aws_lambda_function" "guess_total" {
  function_name = "${var.environment}-${var.project_name}-guess-total"
  handler      = "guess_total.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/guess_total.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/guess_total.py")

  environment {
    variables = local.common_env_vars
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access
  ]
}

# Lambda function for WebSocket connection management
resource "aws_lambda_function" "websocket_handler" {
  function_name = "${var.environment}-${var.project_name}-websocket-handler"
  handler      = "websocket.handler"
  runtime      = var.lambda_runtime
  timeout      = 30
  memory_size  = 128
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/websocket.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/websocket.py")

  environment {
    variables = local.common_env_vars
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.api_gateway_management
  ]
}

# Lambda function for starting the game after delay
resource "aws_lambda_function" "start_game" {
  function_name = "${var.environment}-${var.project_name}-start-game"
  handler      = "start_game.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/start_game.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/start_game.py")

  environment {
    variables = local.common_env_vars
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.api_gateway_management
  ]
}

# Lambda function for handling pick timeouts
resource "aws_lambda_function" "pick_timeout" {
  function_name = "${var.environment}-${var.project_name}-pick-timeout"
  handler      = "pick_timeout.handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  role         = aws_iam_role.lambda_execution_role.arn

  filename         = "${local.lambda_zip_dir}/pick_timeout.zip"
  source_code_hash = filebase64sha256("${local.lambda_source_dir}/pick_timeout.py")

  environment {
    variables = local.common_env_vars
  }

  depends_on = [
    null_resource.create_lambda_zip_dir,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.dynamodb_access,
    aws_iam_role_policy_attachment.api_gateway_management
  ]
}
