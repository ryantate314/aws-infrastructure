terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state: never committed. new-workload.sh replaces __WORKLOAD__ and you set the env.
  backend "s3" {
    bucket       = "ryantate314-tfstate"
    key          = "workloads/__WORKLOAD__/prod/terraform.tfstate" # change prod->dev for the dev stack
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-infrastructure"
      Workload    = var.workload
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

# CloudFront certificates MUST live in us-east-1, regardless of where the rest runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "aws-infrastructure"
      Workload    = var.workload
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name        = "${var.env}-${var.workload}"
  bucket_name = coalesce(var.bucket_name, "${local.name}-site-${data.aws_caller_identity.current.account_id}")
  use_domain  = var.domain_name != null
}
