# SQS module for OpenBI on AWS.
#
# Creates an events queue and a dead-letter queue. Messages that fail
# processing after max_receive_count receives are moved to the DLQ.
#
# Design notes:
#   - Standard (not FIFO) queues. Order is not required for OpenBI events.
#   - SSE-SQS encryption by default (free, always on).
#   - Long polling (20s) enabled by default on the consumer side.
#   - DLQ retention is longer than the main queue, for investigation.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  main_queue_name = "${var.queue_name}-${var.queue_suffix}"
  dlq_name        = "${var.queue_name}-dlq-${var.queue_suffix}"
}

# ----------------------------------------------------------------------
# Dead-letter queue
# ----------------------------------------------------------------------
# Created first so it can be referenced by the main queue's redrive
# policy.

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = var.dlq_message_retention_seconds
  max_message_size          = var.max_message_size_bytes
  receive_wait_time_seconds = var.receive_wait_time_seconds

  sqs_managed_sse_enabled = var.sqs_managed_sse_enabled
  kms_master_key_id       = var.sqs_managed_sse_enabled ? null : var.kms_master_key_id

  tags = merge(var.tags, {
    Name    = local.dlq_name
    Purpose = "dead-letter"
  })
}

# ----------------------------------------------------------------------
# Main queue
# ----------------------------------------------------------------------

resource "aws_sqs_queue" "main" {
  name                       = local.main_queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size_bytes
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  sqs_managed_sse_enabled = var.sqs_managed_sse_enabled
  kms_master_key_id       = var.sqs_managed_sse_enabled ? null : var.kms_master_key_id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name    = local.main_queue_name
    Purpose = "events"
  })
}

# ----------------------------------------------------------------------
# Queue policies
# ----------------------------------------------------------------------
# Two statements on each queue:
#   1. Deny any principal outside the AWS account
#   2. Deny any request not using HTTPS

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonAccountAccess"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main.arn
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonAccountAccess"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.dlq.arn
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.dlq.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
