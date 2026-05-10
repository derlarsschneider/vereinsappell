provider "aws" {
    region = "eu-central-1"
}

variable "aws_region" {
    default = "eu-central-1"
}

terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

locals {
    name_prefix = "vereins-app-beta"
}

data "aws_caller_identity" "current" {}
