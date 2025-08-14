data "archive_file" "lambda_zips" {
    for_each = {
        http_create_game   = "lambda/http_create_game.py"
        http_join_game     = "lambda/http_join_game.py"
        http_pick          = "lambda/http_pick.py"
        http_guess         = "lambda/http_guess.py"
        http_get_state     = "lambda/http_get_state.py"
        ws_on_connect      = "lambda/ws_on_connect.py"
        ws_on_disconnect   = "lambda/ws_on_disconnect.py"
        ws_broadcast       = "lambda/ws_broadcast.py"
        timer_start_game   = "lambda/timer_start_game.py"
        timer_pick_timeout = "lambda/timer_pick_timeout.py"
        timer_guess_timeout= "lambda/timer_guess_timeout.py"
        util_common        = "lambda/common/util.py"
    }
    type        = "zip"
    source_dir  = "lambda"
    output_path = "lambda_package.zip"
}

# Hinweis: Für Einfachheit paketieren wir alles in EIN Zip (alle Handler importieren util.py)

resource "aws_lambda_function" "http_create_game" {
    function_name = "${local.name_prefix}-http-create-game"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "http_create_game.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment {
        variables = {
            TABLE               = aws_dynamodb_table.knobeln.name
            WS_ENDPOINT         = aws_apigatewayv2_stage.ws.invoke_url
            SCHEDULER_ROLE_ARN  = aws_iam_role.scheduler_invoke_role.arn
            HTTP_API_ID         = aws_apigatewayv2_api.http.id
        }
    }
}

resource "aws_lambda_function" "http_join_game" {
    function_name = "${local.name_prefix}-http-join-game"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "http_join_game.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "http_pick" {
    function_name = "${local.name_prefix}-http-pick"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "http_pick.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "http_guess" {
    function_name = "${local.name_prefix}-http-guess"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "http_guess.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "http_get_state" {
    function_name = "${local.name_prefix}-http-get-state"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "http_get_state.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "ws_on_connect" {
    function_name = "${local.name_prefix}-ws-on-connect"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "ws_on_connect.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "ws_on_disconnect" {
    function_name = "${local.name_prefix}-ws-on-disconnect"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "ws_on_disconnect.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "ws_broadcast" {
    function_name = "${local.name_prefix}-ws-broadcast"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "ws_broadcast.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = var.lambda_timeout
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "timer_start_game" {
    function_name = "${local.name_prefix}-timer-start-game"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "timer_start_game.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = 30
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "timer_pick_timeout" {
    function_name = "${local.name_prefix}-timer-pick-timeout"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "timer_pick_timeout.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = 30
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}

resource "aws_lambda_function" "timer_guess_timeout" {
    function_name = "${local.name_prefix}-timer-guess-timeout"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "timer_guess_timeout.handler"
    runtime       = var.lambda_runtime
    filename      = data.archive_file.lambda_zips.output_path
    memory_size   = var.lambda_memory
    timeout       = 30
    environment { variables = aws_lambda_function.http_create_game.environment[0].variables }
}
