resource "aws_secretsmanager_secret" "firebase_credentials" {
    name        = "firebase-credentials"
    description = "Service Account JSON für Firebase Push Notifications"
}

resource "aws_secretsmanager_secret_version" "firebase_credentials_version" {
    secret_id     = aws_secretsmanager_secret.firebase_credentials.id
    secret_string = file("${path.module}/secrets/firebase-service-account.json")
}

resource "aws_iam_policy" "secretsmanager_policy" {
    name = "${local.name_prefix}-lambda-secretsmanager-access"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement: [
            {
                Effect: "Allow",
                Action: [
                    "secretsmanager:GetSecretValue"
                ],
                Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:firebase-credentials*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "secretsmanager_policy_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.secretsmanager_policy.arn
}
