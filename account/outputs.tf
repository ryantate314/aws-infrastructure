output "workload_boundary_policy_name" {
  description = "Attach as permissions_boundary to workload-owned IAM roles."
  value       = aws_iam_policy.workload_boundary.name
}

output "github_role_arns" {
  description = "CI role ARNs (empty unless enable_github_oidc)."
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}

output "cloudtrail_bucket" {
  value = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}
