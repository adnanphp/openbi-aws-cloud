# Inputs for the CloudWatch module.
#
# Creates:
#   - Log groups for each OpenBI service
#   - A dashboard summarizing cluster and service health
#   - Alarms for the three signals that matter most

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "log_retention_days" {
  description = "Retention period for application log groups (days)"
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be one of the values CloudWatch accepts."
  }
}

variable "service_names" {
  description = "Names of the OpenBI services that emit logs"
  type        = list(string)
  default = [
    "fastapi",
    "superset",
    "cluster-autoscaler",
    "external-secrets",
    "aws-load-balancer-controller",
  ]
}

# ----------------------------------------------------------------------
# Alarm thresholds
# ----------------------------------------------------------------------

variable "rds_cpu_alarm_threshold" {
  description = "CPU percentage above which the RDS alarm fires"
  type        = number
  default     = 80
}

variable "alb_5xx_alarm_threshold" {
  description = "5xx error rate percentage above which the ALB alarm fires"
  type        = number
  default     = 5
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN to notify when alarms fire (optional)"
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------
# Resources to monitor
# ----------------------------------------------------------------------
# These come from other modules and are needed for the dashboard panels
# and alarm metrics.

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance identifier"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (added later, when an ALB exists)"
  type        = string
  default     = ""
}

variable "dlq_name" {
  description = "Name of the SQS dead-letter queue"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
