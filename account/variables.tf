variable "region" {
  type        = string
  description = "Primary region."
  default     = "us-east-1"
}

variable "allowed_regions" {
  type        = list(string)
  description = "Regions workload roles may use (enforced by the permissions boundary)."
  default     = ["us-east-1", "us-east-2"]
}

variable "state_bucket_name" {
  type        = string
  description = "State bucket from ../bootstrap (used to scope CI roles)."
  default     = "ryantate314-tfstate"
}

# --- Cost guardrails -------------------------------------------------------------
variable "alert_email" {
  type        = string
  description = "Email for budget and anomaly alerts. Set via TF_VAR_alert_email or an untracked *.tfvars; remote state is not committed."
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly cost budget. Current spend is under $1."
  default     = 10
}

# --- Audit -----------------------------------------------------------------------
variable "enable_cloudtrail" {
  type        = bool
  description = "Multi-region management-event trail (first copy of management events is free; only S3 storage is billed)."
  default     = true
}

variable "cloudtrail_retention_days" {
  type        = number
  description = "Days to keep CloudTrail logs in S3."
  default     = 365
}

# --- Account hardening -----------------------------------------------------------
variable "enable_account_s3_public_access_block" {
  type        = bool
  description = "Account-wide S3 Block Public Access. Safe to enable: the legacy public bucket (ryantate314.net) was deleted 2026-11-09 and all remaining buckets already block public access. Serve public content via CloudFront + OAC instead."
  default     = true
}

variable "enable_ebs_default_encryption" {
  type        = bool
  description = "Encrypt new EBS volumes by default in the primary region."
  default     = true
}

# --- GitHub Actions OIDC (no static keys) ----------------------------------------
variable "enable_github_oidc" {
  type        = bool
  description = "Create the GitHub OIDC provider and plan/apply roles."
  default     = false
}

variable "github_repo" {
  type        = string
  description = "owner/repo allowed to assume the CI roles (required if enable_github_oidc)."
  default     = ""
}
