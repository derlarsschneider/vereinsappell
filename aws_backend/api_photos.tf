resource "aws_s3_bucket" "photos" {
    bucket = "${local.name_prefix}-photos"

    force_destroy = true # erlaubt das Löschen auch bei vorhandenen Objekten
}

resource "aws_s3_bucket_public_access_block" "photos_block_public" {
    bucket                  = aws_s3_bucket.photos.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_apigatewayv2_route" "photos_get" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "GET /photos"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "photos_post" {
    api_id    = aws_apigatewayv2_api.http_api.id
    route_key = "POST /photos"
    target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
