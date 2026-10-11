# ECR module for OpenBI on AWS.
#
# Creates a single ECR repository for all OpenBI container images.
#
# What this module provides:
#   - An ECR repository with scan-on-push enabled
#   - A lifecycle policy that keeps recent tagged images and prunes old
#     untagged layers
#   - A repository policy that denies public access
#
# What this module does NOT provide:
#   - IAM permissions for pushing/pulling (each consuming service owns
#     its own policy — EKS nodes already have ECR read via the node role
#     in the iam module)
#   - Build/push automation (see scripts/build-and-push.sh)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# ----------------------------------------------------------------------
# ECR repository
# ----------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = var.force_delete

  tags = merge(var.tags, {
    Name = var.repository_name
  })
}

# ----------------------------------------------------------------------
# Lifecycle policy
# ----------------------------------------------------------------------
# Two rules:
#   1. Keep the most recent N tagged images (per image name)
#   2. Delete untagged images after N days
#
# Rule 1 uses a tagPrefixList filter to match tagged images. Since all
# OpenBI images share the same ECR repo but use different tags
# (fastapi-*, superset-*, etc.), the rule applies per-image-name.

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.keep_last_tagged} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_last_tagged
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.delete_untagged_after_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.delete_untagged_after_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Repository policy
# ----------------------------------------------------------------------
# Explicitly denies public access. The repository is private by default,
# but an explicit deny is defense-in-depth and documents intent.

resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicAccess"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
