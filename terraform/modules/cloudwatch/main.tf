# CloudWatch module for OpenBI on AWS.
#
# Creates:
#   - Log groups for each service with a common retention policy
#   - A dashboard summarizing cluster, DB, queue, and LB health
#   - Three alarms for the signals that matter most
#
# Design notes:
#   - Log groups are created upfront so IAM policies can reference them
#     and retention is set from day one.
#   - One dashboard, not many. It should answer "is the platform healthy"
#     in one screen.
#   - Three alarms, not twenty. Each has a clear action.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------
# Log groups per service
# ----------------------------------------------------------------------
# One log group per service. Services are configured to write to
# /aws/openbi/<service> when their manifests are applied.

resource "aws_cloudwatch_log_group" "services" {
  for_each = toset(var.service_names)

  name              = "/aws/openbi/${each.value}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name    = "/aws/openbi/${each.value}"
    Service = each.value
  })
}

# ----------------------------------------------------------------------
# SNS topic for alarms
# ----------------------------------------------------------------------
# Alarms publish here. Subscribers (email, Slack, PagerDuty) are added
# separately — often manually to avoid putting email addresses in code.

resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alarms"
  })
}

# ----------------------------------------------------------------------
# Alarms
# ----------------------------------------------------------------------

# RDS CPU high — the DB is the bottleneck for analytical queries.
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU above ${var.rds_cpu_alarm_threshold}% for 10 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-cpu-high"
  })
}

# SQS DLQ depth > 0 — something is failing.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-dlq-not-empty"
  alarm_description   = "Messages present in the dead-letter queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-dlq-not-empty"
  })
}

# ALB 5xx rate — user-facing errors.
# Only created if an ALB exists (alb_arn_suffix is set).
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  count = var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.name_prefix}-alb-5xx-high"
  alarm_description   = "ALB 5xx error rate above ${var.alb_5xx_alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.alb_5xx_alarm_threshold
  treat_missing_data  = "notBreaching"

  # Metric math: (5xx / total) * 100
  metric_query {
    id          = "e1"
    expression  = "(m5xx / mtotal) * 100"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "m5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "mtotal"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-5xx-high"
  })
}

# ----------------------------------------------------------------------
# Dashboard
# ----------------------------------------------------------------------
# A single dashboard with panels for:
#   - EKS cluster: node count, pod count
#   - RDS: CPU, connections
#   - SQS: main queue depth, DLQ depth
#   - Logs: recent errors from any service
#
# Written as JSON (the format AWS uses) but generated from Terraform so
# it's version-controlled.

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-platform"

  dashboard_body = jsonencode({
    widgets = [
      # ---------- Row 1: title ----------
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# OpenBI Platform (${var.name_prefix})\nRegion: ${data.aws_region.current.name} | Cluster: ${var.cluster_name}"
        }
      },

      # ---------- Row 2: EKS ----------
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "EKS — node count"
          region = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", var.cluster_name],
          ]
          view   = "timeSeries"
          stat   = "Average"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "EKS — running pods"
          region = data.aws_region.current.name
          metrics = [
            ["ContainerInsights", "cluster_number_of_running_pods", "ClusterName", var.cluster_name],
          ]
          view   = "timeSeries"
          stat   = "Average"
          period = 300
        }
      },

      # ---------- Row 3: RDS ----------
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "RDS — CPU and connections"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id],
          ]
          view   = "timeSeries"
          stat   = "Average"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "RDS — free storage"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id],
          ]
          view   = "timeSeries"
          stat   = "Average"
          period = 300
        }
      },

      # ---------- Row 4: SQS ----------
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "SQS — main queue depth"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", replace(var.dlq_name, "-dlq", "")],
            ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", replace(var.dlq_name, "-dlq", "")],
          ]
          view   = "timeSeries"
          stat   = "Average"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "SQS — DLQ depth"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name],
          ]
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
        }
      },

      # ---------- Row 5: log errors ----------
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 24
        height = 8
        properties = {
          title  = "Recent errors across services"
          region = data.aws_region.current.name
          query  = "SOURCE '/aws/openbi/fastapi' | SOURCE '/aws/openbi/superset' | fields @timestamp, @logStream, @message | filter @message like /ERROR|error|Error/ | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
