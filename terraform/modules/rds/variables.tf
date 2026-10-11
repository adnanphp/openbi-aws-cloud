# Inputs for the RDS module.
#
# Creates a managed PostgreSQL instance to replace the OpenBI local
# Postgres. The instance lives in private subnets, uses Secrets Manager
# for the master password, and enables IAM database authentication.
#
# What this module provides:
#   - A PostgreSQL RDS instance with a parameter group tuned for
#     analytical workloads
#   - A subnet group spanning the private subnets
#   - A security group allowing access from the cluster's baseline SG
#   - Secrets Manager secret with the master password (managed by RDS)
#   - IAM database authentication enabled
#   - Automated backups (7-day retention by default)
#   - Encryption at rest (AWS-managed KMS key)

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "db_name" {
  description = "Name of the initial database (must be lowercase, alphanumeric)"
  type        = string
  default     = "openbi"
}

variable "master_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "openbiadmin"
}

# ----------------------------------------------------------------------
# Instance sizing
# ----------------------------------------------------------------------

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GB (gp3)"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Upper bound for storage autoscaling (0 disables it)"
  type        = number
  default     = 100
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

# ----------------------------------------------------------------------
# Availability and durability
# ----------------------------------------------------------------------

variable "multi_az" {
  description = "Enable Multi-AZ (doubles cost; recommended for production)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups (0 disables backups)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the instance"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is deleted"
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights (free with 7-day retention)"
  type        = bool
  default     = true
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention"
  type        = number
  default     = 7
}

# ----------------------------------------------------------------------
# Network
# ----------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "RDS requires at least two subnets in different AZs for the subnet group."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach the database (typically the EKS baseline SG)"
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------
# Maintenance
# ----------------------------------------------------------------------

variable "maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
