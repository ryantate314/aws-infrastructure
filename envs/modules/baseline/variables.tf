variable "env" {
  type        = string
  description = "Environment name (dev|prod). Used in names and the /<env>/network/* SSM parameter path."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.env))
    error_message = "env must be lowercase letters, digits and hyphens (2-15 chars)."
  }
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR (/16). Must not overlap other envs, the default VPC (172.31.0.0/16) or the homelab."
}

variable "az_count" {
  type        = number
  description = "Number of AZs (2 is enough for HA at this scale; subnets are free either way)."
  default     = 2
}

variable "enable_flow_logs" {
  type        = bool
  description = "VPC Flow Logs to a lifecycle-managed S3 bucket. Pennies when idle."
  default     = false
}

variable "flow_log_retention_days" {
  type        = number
  default     = 30
  description = "Days to keep flow logs."
}

variable "enable_nat_instance" {
  type        = bool
  description = "Single fck-nat t4g.nano instance (~$3-4/mo) giving the isolated subnets outbound internet. NAT Gateways are forbidden (see docs/cost.md). Off by default; prefer Lambda outside the VPC."
  default     = false
}

variable "interface_endpoint_services" {
  type        = list(string)
  description = "Interface endpoint service short names, e.g. [\"ssm\", \"secretsmanager\"]. Each costs ~$7/mo per AZ, so empty by default."
  default     = []
}
