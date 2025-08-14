terraform {
  backend "s3" {
    bucket         = "vereins-app-675591707882"
    key            = "infra/knobeln/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    use_lockfile   = true
  }
}
