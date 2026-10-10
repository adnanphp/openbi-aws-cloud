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
