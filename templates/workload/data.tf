# Shared network contract published by envs/<env> (see envs/modules/baseline/main.tf).
# Only needed when the workload runs inside the VPC (e.g. Lambda-in-VPC, containers).
# Most serverless workloads should NOT use the VPC: it adds cost/complexity for no benefit.

data "aws_ssm_parameter" "vpc_id" {
  count = var.use_shared_vpc ? 1 : 0
  name  = "/${var.env}/network/vpc_id"
}

data "aws_ssm_parameter" "isolated_subnet_ids" {
  count = var.use_shared_vpc ? 1 : 0
  name  = "/${var.env}/network/isolated_subnet_ids"
}

data "aws_ssm_parameter" "sg_app_id" {
  count = var.use_shared_vpc ? 1 : 0
  name  = "/${var.env}/network/sg_app_id"
}

locals {
  vpc_id              = var.use_shared_vpc ? data.aws_ssm_parameter.vpc_id[0].value : null
  isolated_subnet_ids = var.use_shared_vpc ? split(",", data.aws_ssm_parameter.isolated_subnet_ids[0].value) : []
  sg_app_id           = var.use_shared_vpc ? data.aws_ssm_parameter.sg_app_id[0].value : null
}
