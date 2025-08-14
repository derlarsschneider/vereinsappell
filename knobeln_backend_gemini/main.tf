# main.tf
# Konfiguration des AWS Providers
provider "aws" {
    region = "eu-central-1"
}

# Definition der Ressourcennamen und anderer Variablen
locals {
    project_name = "knobeln"
    api_name     = "${local.project_name}-api"
    ws_api_name  = "${local.project_name}-ws-api"
    stage_name   = "prod"
}

# IAM Rolle für Lambda-Funktionen
# Erlaubt das Schreiben von Logs in CloudWatch und den Zugriff auf DynamoDB und EventBridge
resource "aws_iam_role" "lambda_exec_role" {
    name = "${local.project_name}-lambda-exec-role"

    assume_role_policy = jsonencode({
        Version   = "2012-10-17",
        Statement = [{
            Action    = "sts:AssumeRole",
            Effect    = "Allow",
            Principal = {
                Service = "lambda.amazonaws.com"
            }
        }]
    })
}

# Policy, die den Lambda-Funktionen die notwendigen Berechtigungen gibt
resource "aws_iam_role_policy" "lambda_policy" {
    name = "${local.project_name}-lambda-policy"
    role = aws_iam_role.lambda_exec_role.id

    policy = jsonencode({
        Version   = "2012-10-17",
        Statement = [
            {
                Action   = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                Effect   = "Allow",
                Resource = "arn:aws:logs:*:*:*"
            },
            {
                Action = [
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query"
                ],
                Effect   = "Allow",
                Resource = [
                    aws_dynamodb_table.games_table.arn,
                    aws_dynamodb_table.connections_table.arn
                ]
            },
            {
                Action   = [
                    "events:PutRule",
                    "events:PutTargets",
                    "events:RemoveTargets",
                    "events:DeleteRule"
                ],
                Effect   = "Allow",
                Resource = "arn:aws:events:*:*:rule/${local.project_name}-*"
            },
            {
                Action   = "execute-api:ManageConnections",
                Effect   = "Allow",
                Resource = "arn:aws:execute-api:*:*:${aws_apigatewayv2_api.ws_api.id}/*"
            }
        ]
    })
}

# DynamoDB Tabelle für Spielstände
resource "aws_dynamodb_table" "games_table" {
    name         = "${local.project_name}-games"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "gameId"

    attribute {
        name = "gameId"
        type = "S"
    }
}

# DynamoDB Tabelle für WebSocket-Verbindungen
resource "aws_dynamodb_table" "connections_table" {
    name         = "${local.project_name}-connections"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "connectionId"

    attribute {
        name = "connectionId"
        type = "S"
    }

    global_secondary_index {
        name            = "gameId-index"
        hash_key        = "gameId"
        projection_type = "ALL"
    }
}

# API Gateway (HTTP)
resource "aws_apigatewayv2_api" "http_api" {
    name          = local.api_name
    protocol_type = "HTTP"

    cors_configuration {
        allow_origins = ["https://vereinsappell.web.app", "http://localhost:*"]
        allow_methods = ["POST", "GET", "OPTIONS"]
        allow_headers = ["Content-Type", "Authorization"]
    }
}

resource "aws_apigatewayv2_stage" "http_api_stage" {
    api_id      = aws_apigatewayv2_api.http_api.id
    name        = local.stage_name
    auto_deploy = true
}

# API Gateway (WebSocket)
resource "aws_apigatewayv2_api" "ws_api" {
    name                       = local.ws_api_name
    protocol_type              = "WEBSOCKET"
    route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_stage" "ws_api_stage" {
    api_id      = aws_apigatewayv2_api.ws_api.id
    name        = local.stage_name
    auto_deploy = true
}

# Lambda Funktionen (Platzhalter für die eigentlichen Funktionsdefinitionen)
# Diese werden in einer separaten Datei definiert (lambda.tf)

# outputs.tf
# Gibt die URLs der erstellten APIs aus
output "http_api_endpoint" {
    value = aws_apigatewayv2_stage.http_api_stage.invoke_url
}

output "ws_api_endpoint" {
    value = aws_apigatewayv2_stage.ws_api_stage.invoke_url
}

# lambda.tf
# Erstellt die Lambda-Funktionen und verknüpft sie mit den API-Gateways

# Archiv-Dateien für den Lambda-Code (werden durch das deploy.sh Skript erstellt)
data "archive_file" "game_logic_zip" {
    type        = "zip"
    source_dir  = "${path.module}/lambda/game_logic"
    output_path = "${path.module}/lambda_build/game_logic.zip"
}

data "archive_file" "ws_handler_zip" {
    type        = "zip"
    source_dir  = "${path.module}/lambda/ws_handler"
    output_path = "${path.module}/lambda_build/ws_handler.zip"
}

# --- HTTP API Lambdas ---

# POST /games
resource "aws_lambda_function" "create_game" {
    function_name = "${local.project_name}-create-game"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.handler"
    runtime       = "python3.9"
    filename      = data.archive_file.game_logic_zip.output_path
    source_code_hash = data.archive_file.game_logic_zip.output_base64sha256

    environment {
        variables = {
            GAMES_TABLE_NAME = aws_dynamodb_table.games_table.name
            PROJECT_NAME     = local.project_name
        }
    }
}

# POST /games/{gameId}/join
resource "aws_lambda_function" "join_game" {
    function_name = "${local.project_name}-join-game"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.handler"
    runtime       = "python3.9"
    filename      = data.archive_file.game_logic_zip.output_path
    source_code_hash = data.archive_file.game_logic_zip.output_base64sha256

    environment {
        variables = {
            GAMES_TABLE_NAME      = aws_dynamodb_table.games_table.name
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
            WS_API_ENDPOINT       = "https://${aws_apigatewayv2_api.ws_api.id}.execute-api.${provider.aws.region}.amazonaws.com/${local.stage_name}"
        }
    }
}

# POST /games/{gameId}/pick
resource "aws_lambda_function" "pick_sticks" {
    function_name = "${local.project_name}-pick-sticks"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.handler"
    runtime       = "python3.9"
    filename      = data.archive_file.game_logic_zip.output_path
    source_code_hash = data.archive_file.game_logic_zip.output_base64sha256

    environment {
        variables = {
            GAMES_TABLE_NAME      = aws_dynamodb_table.games_table.name
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
            WS_API_ENDPOINT       = "https://${aws_apigatewayv2_api.ws_api.id}.execute-api.${provider.aws.region}.amazonaws.com/${local.stage_name}"
        }
    }
}

# POST /games/{gameId}/guess
resource "aws_lambda_function" "guess_sticks" {
    function_name = "${local.project_name}-guess-sticks"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.handler"
    runtime       = "python3.9"
    filename      = data.archive_file.game_logic_zip.output_path
    source_code_hash = data.archive_file.game_logic_zip.output_base64sha256

    environment {
        variables = {
            GAMES_TABLE_NAME      = aws_dynamodb_table.games_table.name
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
            WS_API_ENDPOINT       = "https://${aws_apigatewayv2_api.ws_api.id}.execute-api.${provider.aws.region}.amazonaws.com/${local.stage_name}"
        }
    }
}

# Lambda für EventBridge-Trigger (startGame, timeoutPick)
resource "aws_lambda_function" "game_timer_handler" {
    function_name = "${local.project_name}-game-timer-handler"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.handler"
    runtime       = "python3.9"
    filename      = data.archive_file.game_logic_zip.output_path
    source_code_hash = data.archive_file.game_logic_zip.output_base64sha256

    environment {
        variables = {
            GAMES_TABLE_NAME      = aws_dynamodb_table.games_table.name
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
            WS_API_ENDPOINT       = "https://${aws_apigatewayv2_api.ws_api.id}.execute-api.${provider.aws.region}.amazonaws.com/${local.stage_name}"
            PROJECT_NAME          = local.project_name
        }
    }
}

# Berechtigung für EventBridge, die Timer-Lambda aufzurufen
resource "aws_lambda_permission" "allow_eventbridge" {
    statement_id  = "AllowExecutionFromEventBridge"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.game_timer_handler.function_name
    principal     = "events.amazonaws.com"
    source_arn    = "arn:aws:events:${provider.aws.region}:${data.aws_caller_identity.current.account_id}:rule/${local.project_name}-*"
}

data "aws_caller_identity" "current" {}


# --- HTTP API Integrationen ---
resource "aws_apigatewayv2_integration" "create_game_int" {
    api_id           = aws_apigatewayv2_api.http_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.create_game.invoke_arn
    payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "create_game_route" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /games"
    target    = "integrations/${aws_apigatewayv2_integration.create_game_int.id}"
}

# ... (Integrationen und Routen für join, pick, guess wiederholen) ...
# (Aus Platzgründen hier gekürzt, das Muster ist identisch)


# --- WebSocket API Lambdas & Integrationen ---
resource "aws_lambda_function" "ws_connect" {
    function_name = "${local.project_name}-ws-connect"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.connect_handler"
    runtime       = "python3.9"
    filename      = data.archive_file.ws_handler_zip.output_path
    source_code_hash = data.archive_file.ws_handler_zip.output_base64sha256
    environment {
        variables = {
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
        }
    }
}

resource "aws_lambda_function" "ws_disconnect" {
    function_name = "${local.project_name}-ws-disconnect"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.disconnect_handler"
    runtime       = "python3.9"
    filename      = data.archive_file.ws_handler_zip.output_path
    source_code_hash = data.archive_file.ws_handler_zip.output_base64sha256
    environment {
        variables = {
            CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections_table.name
        }
    }
}

resource "aws_lambda_function" "ws_default" {
    function_name = "${local.project_name}-ws-default"
    role          = aws_iam_role.lambda_exec_role.arn
    handler       = "main.default_handler"
    runtime       = "python3.9"
    filename      = data.archive_file.ws_handler_zip.output_path
    source_code_hash = data.archive_file.ws_handler_zip.output_base64sha256
}

# Integrationen
resource "aws_apigatewayv2_integration" "ws_connect_int" {
    api_id           = aws_apigatewayv2_api.ws_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.ws_connect.invoke_arn
}
resource "aws_apigatewayv2_integration" "ws_disconnect_int" {
    api_id           = aws_apigatewayv2_api.ws_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.ws_disconnect.invoke_arn
}
resource "aws_apigatewayv2_integration" "ws_default_int" {
    api_id           = aws_apigatewayv2_api.ws_api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.ws_default.invoke_arn
}

# Routen
resource "aws_apigatewayv2_route" "ws_connect_route" {
    api_id    = aws_apigatewayv2_api.ws_api.id
    route_key = "$connect"
    target    = "integrations/${aws_apigatewayv2_integration.ws_connect_int.id}"
}
resource "aws_apigatewayv2_route" "ws_disconnect_route" {
    api_id    = aws_apigatewayv2_api.ws_api.id
    route_key = "$disconnect"
    target    = "integrations/${aws_apigatewayv2_integration.ws_disconnect_int.id}"
}
resource "aws_apigatewayv2_route" "ws_default_route" {
    api_id    = aws_apigatewayv2_api.ws_api.id
    route_key = "$default"
    target    = "integrations/${aws_apigatewayv2_integration.ws_default_int.id}"
}
