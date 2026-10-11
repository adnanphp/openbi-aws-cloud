# Outputs visible after `terraform apply`.
#
# These are mostly useful as a reference — they show what was created
# and provide IDs that later modules will need.

output "vpc_id" {
  description = "ID of the dev VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnets in the dev VPC"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnets in the dev VPC"
  value       = module.vpc.private_subnet_ids
}

output "baseline_security_group_id" {
  description = "Baseline security group ID"
  value       = module.vpc.baseline_security_group_id
}

# ----------------------------------------------------------------------
# IAM outputs
# ----------------------------------------------------------------------

output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = module.iam.eks_cluster_role_arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node group service role"
  value       = module.iam.eks_node_role_arn
}

# ----------------------------------------------------------------------
# ECR outputs
# ----------------------------------------------------------------------

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

# ----------------------------------------------------------------------
# EKS outputs
# ----------------------------------------------------------------------

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.eks.oidc_provider_arn
}

# ----------------------------------------------------------------------
# S3 outputs
# ----------------------------------------------------------------------

output "s3_raw_bucket" {
  description = "Name of the raw data bucket"
  value       = module.s3.raw_bucket_name
}

output "s3_processed_bucket" {
  description = "Name of the processed data bucket"
  value       = module.s3.processed_bucket_name
}

output "s3_models_bucket" {
  description = "Name of the models bucket"
  value       = module.s3.models_bucket_name
}

# ----------------------------------------------------------------------
# RDS outputs
# ----------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret with the master password"
  value       = module.rds.master_user_secret_arn
  sensitive   = true
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds.security_group_id
}

# ----------------------------------------------------------------------
# SQS outputs
# ----------------------------------------------------------------------

output "sqs_main_queue_url" {
  description = "URL of the events queue"
  value       = module.sqs.main_queue_url
}

output "sqs_dlq_url" {
  description = "URL of the dead-letter queue"
  value       = module.sqs.dlq_url
}

# ----------------------------------------------------------------------
# ALB outputs
# ----------------------------------------------------------------------

output "alb_controller_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller"
  value       = module.alb.controller_role_arn
}

output "alb_certificate_arn" {
  description = "ARN of the ACM certificate (null if not configured)"
  value       = module.alb.certificate_arn
}

# ----------------------------------------------------------------------
# CloudWatch outputs
# ----------------------------------------------------------------------

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.cloudwatch.dashboard_name
}

output "cloudwatch_alarm_topic_arn" {
  description = "SNS topic for CloudWatch alarms"
  value       = module.cloudwatch.alarm_topic_arn
}

# ----------------------------------------------------------------------
# Secrets outputs
# ----------------------------------------------------------------------

output "eso_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator"
  value       = module.secrets.eso_role_arn
}

output "secrets_prefix" {
  description = "Prefix under which OpenBI secrets should be stored"
  value       = module.secrets.secret_path_prefix
}
