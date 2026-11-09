output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "isolated_subnet_ids" {
  value = aws_subnet.isolated[*].id
}

output "security_group_ids" {
  value = {
    web       = aws_security_group.web.id
    app       = aws_security_group.app.id
    endpoints = aws_security_group.endpoints.id
  }
}

output "ssm_parameter_prefix" {
  description = "Workloads read network IDs from here."
  value       = "/${var.env}/network/"
}
