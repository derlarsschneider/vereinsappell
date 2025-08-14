data "aws_iam_policy_document" "lambda_assume" {
    statement {
        actions = ["sts:AssumeRole"]
        principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
    }
}

resource "aws_iam_role" "lambda_exec" {
    name               = "${local.name_prefix}-lambda-exec"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
    role       = aws_iam_role.lambda_exec.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_table_ws_scheduler" {
    statement {
        sid = "DynamoDB"
        actions = [
            "dynamodb:GetItem","dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:DeleteItem",
            "dynamodb:Query","dynamodb:Scan","dynamodb:TransactWriteItems"
        ]
        resources = [aws_dynamodb_table.knobeln.arn, "${aws_dynamodb_table.knobeln.arn}/index/*"]
    }
    statement {
        sid = "WebSocketMgmt"
        actions = ["execute-api:ManageConnections"]
        resources = ["${aws_apigatewayv2_api.ws.execution_arn}/*"]
    }
    statement {
        sid = "SchedulerCtl"
        actions = ["scheduler:CreateSchedule","scheduler:DeleteSchedule","scheduler:GetSchedule"]
        resources = ["*"]
    }
    statement {
        sid = "InvokeLambda"
        actions = ["lambda:InvokeFunction"]
        resources = [
            aws_lambda_function.timer_start_game.arn,
            aws_lambda_function.timer_pick_timeout.arn,
            aws_lambda_function.timer_guess_timeout.arn
        ]
    }
}

resource "aws_iam_policy" "lambda_table_ws_scheduler" {
    name   = "${local.name_prefix}-lambda-policy"
    policy = data.aws_iam_policy_document.lambda_table_ws_scheduler.json
}

resource "aws_iam_role_policy_attachment" "lambda_table_ws_scheduler_attach" {
    role       = aws_iam_role.lambda_exec.name
    policy_arn = aws_iam_policy.lambda_table_ws_scheduler.arn
}

# Role used by EventBridge Scheduler to invoke timer lambdas
data "aws_iam_policy_document" "scheduler_assume" {
    statement {
        actions = ["sts:AssumeRole"]
        principals { type = "Service" identifiers = ["scheduler.amazonaws.com"] }
    }
}

resource "aws_iam_role" "scheduler_invoke_role" {
    name               = "${local.name_prefix}-scheduler-invoke"
    assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_invoke_policy" {
    statement {
        actions   = ["lambda:InvokeFunction"]
        resources = [
            aws_lambda_function.timer_start_game.arn,
            aws_lambda_function.timer_pick_timeout.arn,
            aws_lambda_function.timer_guess_timeout.arn
        ]
    }
}

resource "aws_iam_policy" "scheduler_invoke" {
    name   = "${local.name_prefix}-scheduler-invoke-policy"
    policy = data.aws_iam_policy_document.scheduler_invoke_policy.json
}

resource "aws_iam_role_policy_attachment" "scheduler_invoke_attach" {
    role       = aws_iam_role.scheduler_invoke_role.name
    policy_arn = aws_iam_policy.scheduler_invoke.arn
}
