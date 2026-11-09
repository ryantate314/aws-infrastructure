# Permissions boundary for workload-owned roles. Enforces the cost and safety rules even if
# a workload's own policy is too broad. See docs/security.md and docs/cost.md.

data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid       = "AllowEverythingElse"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyCostlyFixedPriceServices"
    effect = "Deny"
    actions = [
      "ec2:CreateNatGateway",
      "ec2:CreateTransitGateway",
      "ec2:CreateClientVpnEndpoint",
      "ec2:CreateVpnConnection",
      "network-firewall:CreateFirewall",
      "network-firewall:CreateFirewallPolicy",
      "es:CreateDomain",
      "es:CreateElasticsearchDomain",
      "aoss:CreateCollection",
      "redshift:CreateCluster",
      "elasticache:CreateCacheCluster",
      "elasticache:CreateReplicationGroup",
      "kafka:CreateCluster",
      "kafka:CreateClusterV2",
      "directconnect:CreateConnection",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIdentityAndAuditTampering"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "organizations:*",
      "account:*",
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "access-analyzer:DeleteAnalyzer",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyOutsideAllowedRegions"
    effect = "Deny"
    not_actions = [
      "iam:*", "sts:*", "cloudfront:*", "route53:*", "route53domains:*", "route53resolver:*",
      "budgets:*", "ce:*", "support:*", "waf:*", "wafv2:*", "acm:*", "health:*",
      "organizations:*", "account:*", "globalaccelerator:*", "shield:*", "trustedadvisor:*",
      "s3:GetBucketLocation", "s3:ListAllMyBuckets",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "workload-permissions-boundary"
  description = "Boundary for workload roles: no costly fixed-price services, no IAM users/keys, no audit tampering, allowed regions only."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

# --- GitHub Actions OIDC (optional) ----------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  for_each = var.enable_github_oidc ? {
    plan  = "repo:${var.github_repo}:pull_request"
    apply = "repo:${var.github_repo}:ref:refs/heads/main"
  } : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = data.aws_iam_policy_document.github_assume

  name                 = "github-actions-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# plan: read-only everywhere, plus state read/write (the lock file is a write).
resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  count      = var.enable_github_oidc ? 1 : 0
  role       = aws_iam_role.github["plan"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}/*"]
  }
}

resource "aws_iam_role_policy" "github_plan_state" {
  count  = var.enable_github_oidc ? 1 : 0
  name   = "terraform-state"
  role   = aws_iam_role.github["plan"].id
  policy = data.aws_iam_policy_document.github_state.json
}

# apply: only from main. AdministratorAccess is the pragmatic default for a one-person
# account; tighten per docs/security.md once workloads stabilise.
resource "aws_iam_role_policy_attachment" "github_apply_admin" {
  count      = var.enable_github_oidc ? 1 : 0
  role       = aws_iam_role.github["apply"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

check "github_repo_set" {
  assert {
    condition     = !var.enable_github_oidc || var.github_repo != ""
    error_message = "github_repo must be set (owner/repo) when enable_github_oidc is true."
  }
}
