resource "aws_dynamodb_table" "customer_config_table" {
    name         = "vereinsappell-customers"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "application_id"

    attribute {
        name = "application_id"
        type = "S"
    }
}
