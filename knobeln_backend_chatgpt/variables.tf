variable "aws_region" { type = string }
variable "project_name" { type = string }
variable "env" { type = string default = "prod" }
variable "table_billing_mode" { type = string default = "PAY_PER_REQUEST" }
variable "lambda_runtime" { type = string default = "python3.12" }
variable "lambda_memory" { type = number default = 256 }
variable "lambda_timeout" { type = number default = 10 }
