terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Credentials come from the AWS CLI (`aws configure` or `aws sso login`) or
# the AWS_* environment variables; nothing is stored in this repository.
provider "aws" {
  region = var.region

  # Tags applied to every resource that supports them.
  default_tags {
    tags = var.tags
  }
}
