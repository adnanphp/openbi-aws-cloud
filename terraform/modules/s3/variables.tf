# Inputs for the S3 module.
#
# Creates three buckets that mirror the OpenBI data lifecycle:
#   - openbi-raw: landing zone for source data (versioning on)
#   - openbi-processed: cleaned/derived data (versioning off)
#   - openbi-models: trained ML artifacts (versioning on)
#
# Each bucket gets:
#   - Server-side encryption (SSE-S3 by default)
#   - Public access blocked
#   - A lifecycle policy appropriate to its role
#   - A bucket policy denying non-account access

variable "name_prefix" {
  description = "Prefix for resource names (used to name related resources, not the buckets themselves)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

# ----------------------------------------------------------------------
# Bucket names
# ----------------------------------------------------------------------
# S3 bucket names are globally unique across all of AWS. To avoid
# collisions, we append a unique suffix (typically the AWS account ID)
# supplied by the caller.

variable "bucket_suffix" {
  description = "Unique suffix appended to every bucket name (e.g. account ID)"
  type        = string
}

variable "raw_bucket_name" {
  description = "Base name for the raw data bucket"
  type        = string
  default     = "openbi-raw"
}

variable "processed_bucket_name" {
  description = "Base name for the processed data bucket"
  type        = string
  default     = "openbi-processed"
}

variable "models_bucket_name" {
  description = "Base name for the models bucket"
  type        = string
  default     = "openbi-models"
}

# ----------------------------------------------------------------------
# Encryption
# ----------------------------------------------------------------------
# SSE-S3 (AES256) is free and always available. SSE-KMS gives an audit
# trail and lets you control key rotation, at ~$1/key/month plus
# per-request KMS charges.

variable "encryption_type" {
  description = "SSE algorithm: AES256 (SSE-S3) or aws:kms"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_type)
    error_message = "encryption_type must be AES256 or aws:kms."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN (required when encryption_type is aws:kms)"
  type        = string
  default     = null
}

# ----------------------------------------------------------------------
# Lifecycle tuning
# ----------------------------------------------------------------------

variable "raw_transition_ia_days" {
  description = "Days after which raw objects move to Standard-IA"
  type        = number
  default     = 30
}

variable "raw_transition_glacier_days" {
  description = "Days after which raw objects move to Glacier"
  type        = number
  default     = 90
}

variable "raw_expiration_days" {
  description = "Days after which raw objects expire"
  type        = number
  default     = 365
}

variable "processed_expiration_days" {
  description = "Days after which processed objects expire"
  type        = number
  default     = 90
}

variable "models_noncurrent_expiration_days" {
  description = "Days after which non-current model versions expire"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
