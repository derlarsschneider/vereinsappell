resource "aws_dynamodb_table" "knobeln" {
    name         = local.table_name
    billing_mode = var.table_billing_mode
    hash_key     = "PK"
    range_key    = "SK"

    attribute { name = "PK" type = "S" }
    attribute { name = "SK" type = "S" }

    global_secondary_index {
        name               = "GSI1"
        hash_key           = "GSI1PK"
        range_key          = "GSI1SK"
        projection_type    = "ALL"
        write_capacity     = 0
        read_capacity      = 0
    }

    global_secondary_index {
        name               = "GSI2"
        hash_key           = "GSI2PK"
        range_key          = "GSI2SK"
        projection_type    = "ALL"
        write_capacity     = 0
        read_capacity      = 0
    }

    ttl { attribute_name = "ttl" enabled = true }
}
