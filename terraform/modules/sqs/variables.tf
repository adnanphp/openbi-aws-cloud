# Inputs for the SQS module.
#
# Creates an event queue and a dead-letter queue. Consumers that fail to
# process a message after max_receive_count attempts cause it to be
# moved to the DLQ for inspection.
#
# What this module provides:
#   - Main queue (openbi-events-<suffix>) with SSE-SQS encryption
#   - Dead-letter queue (openbi-events-dlq-<suffix>)
#   - Redrive policy routing from main to DLQ
#   - Queue policies denying non-account access and insecure transport
#
# What this module does NOT provide:
#   - IAM policies for producers/consumers (those come as IRSA roles)
#   - S3 event notification wiring (added in Phase A10 when there's a
#     consumer)

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "queue_name" {
  description = "Base name for the main queue"
  type        = string
  default     = "openbi-events"
}

variable "queue_suffix" {
  description = "Suffix appended to the queue name for uniqueness (e.g. AWS account ID)"
  type        = string
}

# ----------------------------------------------------------------------
# Message settings
# ----------------------------------------------------------------------

variable "visibility_timeout_seconds" {
  description = "Time a message is invisible to other consumers after being received"
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "How long SQS retains a message (60 to 1209600 seconds)"
  type        = number
  default     = 345600 # 4 days

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

variable "max_message_size_bytes" {
  description = "Maximum message size in bytes (1024 to 262144)"
  type        = number
  default     = 262144 # 256 KB

  validation {
    condition     = var.max_message_size_bytes >= 1024 && var.max_message_size_bytes <= 262144
    error_message = "max_message_size_bytes must be between 1024 and 262144."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long-poll wait time (0 disables long polling; 20 is the recommended value)"
  type        = number
  default     = 20

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }
}

# ----------------------------------------------------------------------
# Dead-letter queue
# ----------------------------------------------------------------------

variable "max_receive_count" {
  description = "Number of times a message can be received before moving to the DLQ"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "Retention for DLQ messages (typically longer than the main queue, for investigation)"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

# ----------------------------------------------------------------------
# Encryption
# ----------------------------------------------------------------------

variable "sqs_managed_sse_enabled" {
  description = "Use SQS-managed SSE-SQS encryption (free). Set to false and provide kms_master_key_id for SSE-KMS."
  type        = bool
  default     = true
}

variable "kms_master_key_id" {
  description = "KMS key ID or ARN for SSE-KMS (required when sqs_managed_sse_enabled is false)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
