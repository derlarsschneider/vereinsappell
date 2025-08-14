terraform {
    required_version = ">= 1.5.0"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = ">= 5.40"
        }
        archive = {
            source  = "hashicorp/archive"
            version = ">= 2.4.2"
        }
    }
}

provider "aws" {
    region = var.aws_region
}

locals {
    name_prefix = "${var.project_name}-${var.env}"
}
