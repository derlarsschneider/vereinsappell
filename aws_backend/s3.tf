resource "aws_s3_bucket" "s3_bucket" {
    bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"

    force_destroy = true # erlaubt das Löschen auch bei vorhandenen Objekten
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_block_public" {
    bucket                  = aws_s3_bucket.s3_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "s3_bucket_cors" {
    bucket = aws_s3_bucket.s3_bucket.id

    cors_rule {
        allowed_headers = ["*"]
        allowed_methods = ["GET", "HEAD"]
        allowed_origins = [
            "https://vereinsappell.web.app",
            "https://vereinsappell--*.web.app",
        ]
        max_age_seconds = 3600
    }
}
