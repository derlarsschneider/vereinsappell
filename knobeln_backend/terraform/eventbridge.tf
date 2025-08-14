# EventBridge Rule for starting a game after the delay
resource "aws_cloudwatch_event_rule" "start_game" {
  name                = "${var.environment}-knobeln-start-game"
  description         = "Trigger to start a Knobeln game after the initial delay"
  schedule_expression = "rate(1 minute)"  # This will be overridden by the target input
  
  tags = {
    Environment = var.environment
    Name        = "${var.environment}-knobeln-start-game"
  }
}

resource "aws_cloudwatch_event_target" "start_game" {
  rule      = aws_cloudwatch_event_rule.start_game.name
  target_id = "StartGameLambda"
  arn       = aws_lambda_function.start_game.arn
  
  input = jsonencode({
    "source" : "knobeln.game",
    "detail-type" : "GameStartScheduled",
    "detail" : {
      "gameId" : "PLACEHOLDER_GAME_ID"  # Will be overridden by the Lambda
    }
  })
}

# EventBridge Rule for handling pick timeouts
resource "aws_cloudwatch_event_rule" "pick_timeout" {
  name                = "${var.environment}-knobeln-pick-timeout"
  description         = "Trigger when a player takes too long to pick sticks"
  schedule_expression = "rate(1 minute)"  # This will be overridden by the target input
  
  tags = {
    Environment = var.environment
    Name        = "${var.environment}-knobeln-pick-timeout"
  }
}

resource "aws_cloudwatch_event_target" "pick_timeout" {
  rule      = aws_cloudwatch_event_rule.pick_timeout.name
  target_id = "PickTimeoutLambda"
  arn       = aws_lambda_function.pick_timeout.arn
  
  input = jsonencode({
    "source" : "knobeln.game",
    "detail-type" : "PickTimeoutScheduled",
    "detail" : {
      "gameId" : "PLACEHOLDER_GAME_ID",  # Will be overridden by the Lambda
      "playerId" : "PLACEHOLDER_PLAYER_ID"  # Will be overridden by the Lambda
    }
  })
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_start_game" {
  statement_id  = "AllowExecutionFromEventBridge_StartGame"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_game.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_game.arn
}

resource "aws_lambda_permission" "allow_eventbridge_pick_timeout" {
  statement_id  = "AllowExecutionFromEventBridge_PickTimeout"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pick_timeout.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pick_timeout.arn
}
