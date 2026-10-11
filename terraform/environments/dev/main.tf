# OpenBI AWS — dev environment
#
# This is the composition layer. It wires together the modules with
# environment-specific values.
#
# Phase A1 (current): VPC only.
# Future phases add: EKS, ECR, RDS, S3, SQS, ALB, IAM, CloudWatch.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # NOTE: no backend configured. For local validation we use
  # `terraform init -backend=false`. A real deployment would configure
  # an S3 backend with DynamoDB locking (see docs/architecture.md).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = "openbi"
    Environment = "dev"
    ManagedBy   = "terraform"
    Repository  = "github.com/adnanphp/openbi-aws-cloud"
  }

  name_prefix = "openbi-dev"
}

# ----------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]

  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

  single_nat_gateway       = true
  enable_flow_logs         = true
  flow_logs_retention_days = 7

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# IAM
# ----------------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# ECR
# ----------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  name_prefix     = local.name_prefix
  repository_name = "openbi"

  # Dev convenience: allow `terraform destroy` even with images present.
  force_delete = true

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# EKS
# ----------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  name_prefix        = local.name_prefix
  cluster_name       = "openbi-dev"
  kubernetes_version = "1.30"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn

  # Private endpoint only by default.
  endpoint_private_access = true
  endpoint_public_access  = false

  # All five control plane log types, 7-day retention.
  enabled_cluster_log_types  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_days = 7

  # Small dev cluster: 1 on-demand node (critical), 0-3 spot nodes (workloads).
  on_demand_instance_types = ["t3.medium"]
  on_demand_desired_size   = 1
  on_demand_min_size       = 1
  on_demand_max_size       = 2

  spot_instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
  spot_desired_size   = 1
  spot_min_size       = 0
  spot_max_size       = 3

  node_disk_size_gb = 30

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# S3
# ----------------------------------------------------------------------

module "s3" {
  source = "../../modules/s3"

  name_prefix   = local.name_prefix
  bucket_suffix = var.bucket_suffix

  # Default encryption: SSE-S3 (free, always on).
  # To use SSE-KMS instead, set:
  #   encryption_type = "aws:kms"
  #   kms_key_arn     = <your key ARN>
  encryption_type = "AES256"

  # Lifecycle tuning (defaults match the module).
  raw_transition_ia_days      = 30
  raw_transition_glacier_days = 90
  raw_expiration_days         = 365
  processed_expiration_days   = 90

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# RDS
# ----------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  name_prefix     = local.name_prefix
  db_name         = "openbi"
  master_username = "openbiadmin"
  instance_class  = "db.t4g.micro"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Allow the cluster baseline SG to reach the DB.
  allowed_security_group_ids = [module.vpc.baseline_security_group_id]

  # Dev sizing: single-AZ, no deletion protection, no final snapshot.
  multi_az                 = false
  backup_retention_days    = 7
  deletion_protection      = false
  skip_final_snapshot      = true
  allocated_storage_gb     = 20
  max_allocated_storage_gb = 100

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# SQS
# ----------------------------------------------------------------------

module "sqs" {
  source = "../../modules/sqs"

  name_prefix  = local.name_prefix
  queue_name   = "openbi-events"
  queue_suffix = var.bucket_suffix # reuse the same uniqueness suffix

  # Long polling enabled by default.
  receive_wait_time_seconds = 20

  # Standard SQS retention defaults; DLQ retains longer.
  message_retention_seconds     = 345600  # 4 days
  dlq_message_retention_seconds = 1209600 # 14 days
  max_receive_count             = 3

  # SSE-SQS encryption (free, always on).
  sqs_managed_sse_enabled = true

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# ALB / Ingress
# ----------------------------------------------------------------------

module "alb" {
  source = "../../modules/alb"

  name_prefix  = local.name_prefix
  cluster_name = module.eks.cluster_name

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # HTTPS is opt-in. Leave domain_name empty for HTTP-only.
  # To enable HTTPS:
  #   domain_name       = "openbi.example.com"
  #   route53_zone_id   = "Z0123456789ABC"
  domain_name = ""
  # subject_alternative_names = ["*.openbi.example.com"]
  # route53_zone_id = "..."

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# CloudWatch
# ----------------------------------------------------------------------

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name_prefix = local.name_prefix

  # Log retention: 14 days for application logs.
  log_retention_days = 14

  # Service log groups.
  service_names = [
    "fastapi",
    "superset",
    "cluster-autoscaler",
    "external-secrets",
    "aws-load-balancer-controller",
  ]

  # Alarm thresholds.
  rds_cpu_alarm_threshold = 80
  alb_5xx_alarm_threshold = 5

  # Resources to monitor.
  cluster_name   = module.eks.cluster_name
  db_instance_id = module.rds.db_instance_id
  dlq_name       = module.sqs.dlq_name

  # ALB arn suffix is added later, once an ALB exists.
  alb_arn_suffix = ""

  tags = local.common_tags
}

# ----------------------------------------------------------------------
# Secrets Manager (External Secrets Operator IRSA role)
# ----------------------------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"

  name_prefix = local.name_prefix

  secret_path_prefix = "openbi/dev"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # External Secrets Operator runs in this namespace with this
  # ServiceAccount (installed via Helm — see kubernetes/external-secrets/).
  external_secrets_namespace       = "external-secrets"
  external_secrets_service_account = "external-secrets"

  tags = local.common_tags
}
