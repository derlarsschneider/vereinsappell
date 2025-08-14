# Knobeln Game Backend

This repository contains the Terraform configuration and Lambda function code for the Knobeln game backend, deployed on AWS.

## Architecture

The backend consists of the following AWS services:

- **API Gateway (HTTP & WebSocket)**: Handles RESTful API requests and real-time WebSocket connections
- **AWS Lambda**: Serverless functions for game logic
- **DynamoDB**: Persistent storage for game state and player information
- **EventBridge**: Manages game timers and state transitions
- **CloudWatch**: Logging and monitoring

## Prerequisites

1. [Terraform](https://www.terraform.io/downloads.html) (>= 1.2.0)
2. [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
3. AWS IAM permissions to create and manage the resources
4. A configured S3 bucket for Terraform remote state
5. A configured Cognito User Pool for authentication

## Setup

1. Clone the repository
2. Navigate to the `terraform` directory
3. Create a `terraform.tfvars` file with your configuration:

```hcl
environment = "dev"
aws_region = "eu-central-1"
cognito_user_pool_id = "your-user-pool-id"
cognito_user_pool_client_id = "your-client-id"
```

4. Initialize Terraform:

```bash
terraform init -backend-config="bucket=your-terraform-state-bucket" \
               -backend-config="key=knobeln/terraform.tfstate" \
               -backend-config="region=eu-central-1"
```

5. Review the planned changes:

```bash
terraform plan
```

6. Apply the configuration:

```bash
terraform apply
```

## Infrastructure Components

### DynamoDB Table

- **Table Name**: `{environment}-knobeln-games`
- **Partition Key**: `game_id` (String)
- **Sort Key**: `sk` (String)
- **GSI**: `StatusIndex` on `status` attribute

### API Endpoints

#### HTTP API

- `POST /games` - Create a new game
- `POST /games/{gameId}/join` - Join an existing game
- `POST /games/{gameId}/pick` - Pick sticks
- `POST /games/{gameId}/guess` - Guess the total number of sticks
- `GET /games/{gameId}` - Get game status

#### WebSocket API

- `$connect` - Handle new WebSocket connections
- `$disconnect` - Handle WebSocket disconnections
- `$default` - Default route for messages
- `sendmessage` - Custom route for game messages

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DYNAMODB_TABLE` | Name of the DynamoDB table | Automatically set |
| `WEBSOCKET_API` | WebSocket API endpoint | Automatically set |
| `STAGE` | Deployment environment (dev/staging/prod) | Value of `var.environment` |
| `GAME_START_DELAY` | Delay before game starts (seconds) | 60 |
| `PICK_TIMEOUT` | Timeout for picking sticks (seconds) | 30 |

## Deployment

1. Make your changes to the Terraform configuration
2. Run `terraform plan` to review changes
3. Run `terraform apply` to apply changes
4. Deploy Lambda function code using the deployment script:

```bash
./deploy.sh
```

## Cleanup

To destroy all created resources:

```bash
terraform destroy
```

## Security

- All API endpoints require JWT authentication via Cognito
- CORS is configured to only allow requests from specified origins
- IAM policies follow the principle of least privilege

## Monitoring

- CloudWatch Logs are enabled for all Lambda functions and API Gateway
- Metrics are available in CloudWatch for monitoring

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
