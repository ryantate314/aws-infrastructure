variable "workload" {
  type        = string
  description = "Workload name, lowercase-with-hyphens. Set by scripts/new-workload.sh."
  default     = "__WORKLOAD__"
}

variable "env" {
  type        = string
  description = "dev or prod. Must match the shared baseline you deployed in envs/<env>."
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Override the generated bucket name (e.g. to import an existing bucket)."
  default     = null
}

variable "domain_name" {
  type        = string
  description = "Custom domain (e.g. www.example.com). null = use the *.cloudfront.net URL, no cert."
  default     = null
}

variable "hosted_zone_id" {
  type        = string
  description = "Route 53 zone ID for domain_name (the zone already exists; reference it, don't create it)."
  default     = null
}

variable "price_class" {
  type        = string
  description = "PriceClass_100 = US/Canada/Europe edges only, the cheapest."
  default     = "PriceClass_100"
}

variable "use_shared_vpc" {
  type        = bool
  description = "Read the shared baseline VPC IDs from SSM. Keep false for pure S3/CloudFront/Lambda-outside-VPC workloads (the cheapest design)."
  default     = false
}

variable "enable_deploy_role" {
  type        = bool
  description = "Create a GitHub Actions role that can sync the site and invalidate CloudFront (replaces static IAM user keys). Needs account/ with enable_github_oidc."
  default     = false
}

variable "github_repo" {
  type        = string
  description = "owner/repo allowed to deploy (required if enable_deploy_role)."
  default     = ""
}
