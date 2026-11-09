terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name   = "shared-${var.env}"
  azs    = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  region = data.aws_region.current.region

  # /24 per subnet: public = .0-.N, isolated = .10-.10+N
  public_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, i)]
  isolated_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, 10 + i)]
}

# --- VPC -------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = local.name }
}

# Default SG: no rules at all, so nothing can accidentally use it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-default-deny" }
}

# --- Subnets & routing -----------------------------------------------------------

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false # resources opt in explicitly

  tags = { Name = "${local.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "isolated" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = local.isolated_cidrs[count.index]

  tags = { Name = "${local.name}-isolated-${local.azs[count.index]}", Tier = "isolated" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Isolated: no internet route unless the optional NAT instance is enabled.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-isolated" }
}

resource "aws_route_table_association" "isolated" {
  count          = var.az_count
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}

# --- Free gateway endpoints ------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.isolated.id]

  tags = { Name = "${local.name}-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.isolated.id]

  tags = { Name = "${local.name}-dynamodb" }
}

# --- Security groups (least privilege; reference SGs, not CIDRs, where possible) ----

resource "aws_security_group" "web" {
  name_prefix = "${local.name}-web-"
  description = "Public HTTPS ingress for internet-facing resources (use only if a workload needs it)"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-web" }
}

resource "aws_vpc_security_group_ingress_rule" "web_https_v4" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "web_https_v6" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from the internet (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_egress_rule" "web_to_app" {
  security_group_id            = aws_security_group.web.id
  description                  = "To app tier"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-app-"
  description = "App tier (Lambda-in-VPC, containers). No ingress by default."
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_web" {
  security_group_id            = aws_security_group.app.id
  description                  = "From web tier"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.web.id
}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${local.region}.s3"
}

data "aws_prefix_list" "dynamodb" {
  name = "com.amazonaws.${local.region}.dynamodb"
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 via gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_dynamodb" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to DynamoDB via gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.dynamodb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS to interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name}-endpoints-"
  description = "Interface VPC endpoints: HTTPS from the app tier only"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_app" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.app.id
}

# --- Optional paid interface endpoints (default none) ----------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.isolated[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-${each.value}" }
}

# --- Optional NAT instance (fck-nat) ---------------------------------------------
# A NAT *Gateway* costs ~$32+/mo and is forbidden by policy. This is a ~$3-4/mo
# alternative for the rare workload that truly needs VPC egress. Single AZ by design.

data "aws_ami" "fck_nat" {
  count       = var.enable_nat_instance ? 1 : 0
  most_recent = true
  owners      = ["568608671756"] # fck-nat publisher

  filter {
    name   = "name"
    values = ["fck-nat-al2023-hvm-*-arm64-ebs"]
  }
}

resource "aws_security_group" "nat" {
  count       = var.enable_nat_instance ? 1 : 0
  name_prefix = "${local.name}-nat-"
  description = "NAT instance: accept all from VPC, egress to internet"
  vpc_id      = aws_vpc.this.id

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-nat" }
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  count             = var.enable_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "From VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "nat_out" {
  count             = var.enable_nat_instance ? 1 : 0
  security_group_id = aws_security_group.nat[0].id
  description       = "To internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "nat_assume" {
  count = var.enable_nat_instance ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nat" {
  count              = var.enable_nat_instance ? 1 : 0
  name               = "${local.name}-nat"
  assume_role_policy = data.aws_iam_policy_document.nat_assume[0].json
}

# Admin access is via SSM Session Manager only (no SSH, no key pair).
resource "aws_iam_role_policy_attachment" "nat_ssm" {
  count      = var.enable_nat_instance ? 1 : 0
  role       = aws_iam_role.nat[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  count = var.enable_nat_instance ? 1 : 0
  name  = "${local.name}-nat"
  role  = aws_iam_role.nat[0].name
}

resource "aws_instance" "nat" {
  count = var.enable_nat_instance ? 1 : 0

  ami                         = data.aws_ami.fck_nat[0].id
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  iam_instance_profile        = aws_iam_instance_profile.nat[0].name
  associate_public_ip_address = true
  source_dest_check           = false

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "${local.name}-nat" }
}

resource "aws_route" "isolated_nat" {
  count                  = var.enable_nat_instance ? 1 : 0
  route_table_id         = aws_route_table.isolated.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

# --- Optional flow logs to S3 ----------------------------------------------------

resource "aws_s3_bucket" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = "${local.name}-flow-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count                   = var.enable_flow_logs ? 1 : 0
  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}

    expiration {
      days = var.flow_log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "flow_logs_bucket" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs[0].arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.flow_logs[0].arn, "${aws_s3_bucket.flow_logs[0].arn}/*"]

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

resource "aws_s3_bucket_policy" "flow_logs" {
  count      = var.enable_flow_logs ? 1 : 0
  bucket     = aws_s3_bucket.flow_logs[0].id
  policy     = data.aws_iam_policy_document.flow_logs_bucket[0].json
  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs[0].arn

  depends_on = [aws_s3_bucket_policy.flow_logs]
}

# --- Contract for workloads: SSM parameters under /<env>/network/* ----------------
# Workloads read these with data sources (free, decoupled, no remote-state coupling).

locals {
  published = {
    vpc_id               = aws_vpc.this.id
    vpc_cidr             = aws_vpc.this.cidr_block
    public_subnet_ids    = join(",", aws_subnet.public[*].id)
    isolated_subnet_ids  = join(",", aws_subnet.isolated[*].id)
    sg_web_id            = aws_security_group.web.id
    sg_app_id            = aws_security_group.app.id
    sg_endpoints_id      = aws_security_group.endpoints.id
    isolated_route_table = aws_route_table.isolated.id
  }
}

resource "aws_ssm_parameter" "network" {
  for_each = local.published

  name  = "/${var.env}/network/${each.key}"
  type  = "String"
  value = each.value
}
