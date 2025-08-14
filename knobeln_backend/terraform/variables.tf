variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "knobeln"
}

variable "allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = [
    "https://vereinsappell.web.app",
    "https://vereinsappell.derlarsschneider.de"
  ]
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
}

variable "game_start_delay_seconds" {
  description = "Delay in seconds before a game starts after creation"
  type        = number
  default     = 60
}

variable "pick_timeout_seconds" {
  description = "Timeout in seconds for players to pick sticks"
  type        = number
  default     = 30
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for JWT authentication"
  type        = string
  default     = ""
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID for JWT authentication"
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = [
    "https://vereinsappell.web.app",
    "https://vereinsappell.derlarsschneider.de"
  ]
}
