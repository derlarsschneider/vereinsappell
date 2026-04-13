aws logs filter-log-events \
    --log-group-name /aws/lambda/vereins-app-beta-lambda_backend \
    --start-time $(date -d '30 minutes ago' +%s000) \
    --filter-pattern "?ERROR ?Error ?error ?Exception ?import" \
    --region eu-central-1 \
    --output text
