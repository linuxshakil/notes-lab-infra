terraform {
  required_version = ">= 1.10"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "notes-lab"
      ManagedBy = "terraform"
      Layer     = "addons"
    }
  }
}

# Read the platform layer's outputs (cluster endpoint, role ARNs ...)
data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/terraform.tfstate"
    region = var.region
  }
}

locals {
  p = data.terraform_remote_state.platform.outputs
}

provider "helm" {
  kubernetes {
    host                   = local.p.cluster_endpoint
    cluster_ca_certificate = base64decode(local.p.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.p.cluster_name, "--region", var.region]
    }
  }
}
