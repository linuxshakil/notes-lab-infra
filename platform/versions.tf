terraform {
  required_version = ">= 1.10"

  # Values come from backend.hcl:  terraform init -backend-config=backend.hcl
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Layer     = "platform"
    }
  }
}

data "aws_caller_identity" "current" {}
