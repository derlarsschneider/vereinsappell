#!/usr/bin/env bash
# Create (or update) the IAM user and policy used by GitHub Actions for CI/CD.
# Idempotent: safe to run multiple times.
#
# Usage:
#   ./create_ci_user.sh [--rotate-key]
#
# On first run:       creates user, policy, access key and prints the key.
# On re-runs:         updates the policy document; asks whether to rotate the key.
# --rotate-key flag:  rotates the key non-interactively (e.g. from another script).

set -euo pipefail

ROTATE_KEY=false
for arg in "$@"; do
  case "$arg" in
    --rotate-key) ROTATE_KEY=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

REGION="eu-central-1"
USER_NAME="vereinsappell-ci"
POLICY_NAME="vereinsappell-ci-deploy"
TF_STATE_BUCKET="vereins-app-675591707882"
ACCOUNT_ID=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo ">>> Account:  $ACCOUNT_ID"
echo ">>> User:     $USER_NAME"
echo ">>> Policy:   $POLICY_NAME"
echo ""

# ── IAM User ──────────────────────────────────────────────────────────────────

if aws iam get-user --user-name "$USER_NAME" &>/dev/null; then
  echo ">>> User already exists, skipping creation."
else
  echo ">>> Creating IAM user..."
  aws iam create-user --user-name "$USER_NAME"
fi

# ── Policy Document ───────────────────────────────────────────────────────────

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketVersioning"
      ],
      "Resource": [
        "arn:aws:s3:::${TF_STATE_BUCKET}",
        "arn:aws:s3:::${TF_STATE_BUCKET}/*"
      ]
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:GetPolicy",
        "lambda:ListVersionsByFunction",
        "lambda:PublishVersion",
        "lambda:GetFunctionCodeSigningConfig",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ApiGateway",
      "Effect": "Allow",
      "Action": "apigateway:*",
      "Resource": "*"
    },
    {
      "Sid": "DynamoDB",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "dynamodb:ListTagsOfResource",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "dynamodb:DescribeContinuousBackups",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTimeToLive"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3AppBuckets",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::vereins-app-*",
        "arn:aws:s3:::vereins-app-*/*"
      ]
    },
    {
      "Sid": "IAM",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:ListPolicyVersions",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:TagResource",
        "secretsmanager:UntagResource",
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:PutResourcePolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EventBridge",
      "Effect": "Allow",
      "Action": [
        "events:PutRule",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:ListTargetsByRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:ListTagsForResource",
        "events:TagResource",
        "events:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ACM",
      "Effect": "Allow",
      "Action": [
        "acm:RequestCertificate",
        "acm:DeleteCertificate",
        "acm:DescribeCertificate",
        "acm:ListCertificates",
        "acm:ListTagsForCertificate",
        "acm:AddTagsToCertificate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53",
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:GetChange",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource",
        "route53:ChangeTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:ListTagsLogGroup",
        "logs:TagResource",
        "logs:UntagResource",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:CreateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# ── Create or update policy ───────────────────────────────────────────────────

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
  echo ">>> Policy already exists, updating..."
  # IAM policies keep up to 5 versions; delete the oldest non-default one first
  # if we are already at the limit.
  VERSION_COUNT=$(aws iam list-policy-versions \
    --policy-arn "$POLICY_ARN" \
    --query 'length(Versions)' \
    --output text)
  if [ "$VERSION_COUNT" -ge 5 ]; then
    OLDEST=$(aws iam list-policy-versions \
      --policy-arn "$POLICY_ARN" \
      --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate) | [0].VersionId' \
      --output text)
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$OLDEST"
  fi
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "$POLICY_DOC" \
    --set-as-default
else
  echo ">>> Creating IAM policy..."
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC"
fi

# ── Attach policy (attach-user-policy is idempotent) ─────────────────────────

echo ">>> Attaching policy to user..."
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$POLICY_ARN"

# ── Access Keys ───────────────────────────────────────────────────────────────

KEY_COUNT=$(aws iam list-access-keys \
  --user-name "$USER_NAME" \
  --query 'length(AccessKeyMetadata)' \
  --output text)

if [ "$KEY_COUNT" -gt 0 ] && [ "$ROTATE_KEY" = false ]; then
  echo ""
  echo ">>> Access key already exists."
  read -r -p "    Rotate key? Old key will be deleted immediately. [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] && ROTATE_KEY=true
fi

if [ "$KEY_COUNT" -gt 0 ] && [ "$ROTATE_KEY" = true ]; then
  echo ">>> Deleting existing access keys..."
  aws iam list-access-keys \
    --user-name "$USER_NAME" \
    --query 'AccessKeyMetadata[*].AccessKeyId' \
    --output text \
  | tr '\t' '\n' \
  | while read -r KEY_ID; do
      aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$KEY_ID"
      echo "    Deleted $KEY_ID"
    done
  KEY_COUNT=0
fi

if [ "$KEY_COUNT" -eq 0 ]; then
  echo ">>> Creating access key..."
  KEYS=$(aws iam create-access-key \
    --user-name "$USER_NAME" \
    --query 'AccessKey.{id:AccessKeyId,secret:SecretAccessKey}' \
    --output json)

  KEY_ID=$(echo "$KEYS" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  SECRET=$(echo "$KEYS" | python3 -c "import json,sys; print(json.load(sys.stdin)['secret'])")

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Add these as GitHub Actions secrets (Settings → Secrets)   ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  printf "║  %-20s  %-38s║\n" "AWS_ACCESS_KEY_ID" "$KEY_ID"
  printf "║  %-20s  %-38s║\n" "AWS_SECRET_ACCESS_KEY" "$SECRET"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "⚠️  Save the secret key now — it cannot be retrieved again."
fi

echo ""
echo "✅ Done."
