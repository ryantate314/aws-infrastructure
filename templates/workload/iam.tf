# Optional CI deploy role: replaces long-lived IAM user keys (e.g. photosite-uploader).
# Requires account/ applied with enable_github_oidc = true. The permissions boundary
# caps the role even if its policy is later widened by mistake.

data "aws_iam_openid_connect_provider" "github" {
  count = var.enable_deploy_role ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy" "boundary" {
  count = var.enable_deploy_role ? 1 : 0
  name  = "workload-permissions-boundary"
}

data "aws_iam_policy_document" "deploy_assume" {
  count = var.enable_deploy_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count = var.enable_deploy_role ? 1 : 0

  name                 = "${local.name}-deploy"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume[0].json
  permissions_boundary = data.aws_iam_policy.boundary[0].arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  count = var.enable_deploy_role ? 1 : 0

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  count  = var.enable_deploy_role ? 1 : 0
  name   = "deploy-site"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy[0].json
}

check "deploy_inputs" {
  assert {
    condition     = !var.enable_deploy_role || var.github_repo != ""
    error_message = "github_repo is required when enable_deploy_role is true."
  }
}
