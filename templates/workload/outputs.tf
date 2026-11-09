output "site_bucket" {
  value = aws_s3_bucket.site.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "url" {
  value = local.use_domain ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "deploy_role_arn" {
  value = var.enable_deploy_role ? aws_iam_role.deploy[0].arn : null
}

output "shared_vpc_id" {
  description = "Set only when use_shared_vpc = true."
  value       = local.vpc_id
}
