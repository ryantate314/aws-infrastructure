terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Intentionally LOCAL state. This root creates the remote-state bucket, so it cannot
  # use it. terraform.tfstate is committed to git: this root must never contain secrets
  # or PII (no emails, tokens, passwords). Everything else uses the S3 backend.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-infrastructure"
      Component = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type        = string
  description = "Region for the state bucket."
  default     = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique name of the Terraform state bucket. Must match backend.tf in every other root."
  default     = "ryantate314-tfstate"
}

variable "noncurrent_version_retention_days" {
  type        = number
  description = "Days to keep old state versions (recovery window)."
  default     = 90
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (free) rather than a customer KMS key (~$1/month). See docs/adr/0001-state-handling.md.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  description = "Use as `bucket` in every other root's backend block."
  value       = aws_s3_bucket.state.id
}

output "region" {
  value = var.region
}
