terraform {
    required_version = ">= 1.3.0"

    backend "s3" {
        bucket         = "vereins-app-675591707882"
        key            = "infra/fines/terraform.tfstate"
        region         = "eu-central-1"
        encrypt        = true
        use_lockfile   = true
    }
}
