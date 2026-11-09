terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state: never committed. Bucket is created by ../../bootstrap.
  backend "s3" {
    bucket       = "ryantate314-tfstate"
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "aws-infrastructure"
      Component   = "baseline"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "baseline" {
  source = "../modules/baseline"

  env        = "dev"
  cidr_block = "10.10.0.0/16"

  enable_flow_logs    = false
  enable_nat_instance = false
}

output "vpc_id" {
  value = module.baseline.vpc_id
}

output "ssm_parameter_prefix" {
  value = module.baseline.ssm_parameter_prefix
}
