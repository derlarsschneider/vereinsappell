resource "aws_iam_role" "lambda_role" {
    name = "${local.name_prefix}-lambda_role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            },
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dynamodb_full_access_policy_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_policy" "s3_policy" {
    name = "AllowLambdaPhotoUpload"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Action = [
                    "s3:ListBucket"
                ],
                Resource = aws_s3_bucket.photos.arn
            },
            {
                Effect = "Allow",
                Action = [
                    "s3:PutObject",
                    "s3:GetObject"
                ],
                Resource = "${aws_s3_bucket.photos.arn}/photos/*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.s3_policy.arn
}
