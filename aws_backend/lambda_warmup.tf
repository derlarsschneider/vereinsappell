resource "aws_cloudwatch_event_rule" "warmup" {
    name                = "${local.name_prefix}-warmup"
    schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "warmup_backend" {
    rule = aws_cloudwatch_event_rule.warmup.name
    arn  = aws_lambda_function.lambda_backend.arn
}

resource "aws_cloudwatch_event_target" "warmup_authorizer" {
    rule = aws_cloudwatch_event_rule.warmup.name
    arn  = aws_lambda_function.lambda_authorizer.arn
}

resource "aws_lambda_permission" "allow_eventbridge_warmup_backend" {
    statement_id  = "AllowEventBridgeWarmupBackend"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_backend.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.warmup.arn
}

resource "aws_lambda_permission" "allow_eventbridge_warmup_authorizer" {
    statement_id  = "AllowEventBridgeWarmupAuthorizer"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_authorizer.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.warmup.arn
}
