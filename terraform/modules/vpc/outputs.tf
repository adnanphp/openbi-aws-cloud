# Outputs from the VPC module.
#
# These are consumed by downstream modules (EKS, RDS, ALB) so they can
# place resources in the correct subnets and reference the correct
# security groups.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability zones used"
  value       = var.availability_zones
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateway(s)"
  value       = aws_nat_gateway.this[*].id
}

output "baseline_security_group_id" {
  description = "ID of the baseline security group"
  value       = aws_security_group.baseline.id
}

output "flow_logs_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Flow Logs (null if disabled)"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}
