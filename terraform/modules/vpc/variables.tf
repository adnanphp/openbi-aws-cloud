# Inputs for the VPC module.
#
# The module is designed for a single-environment VPC (dev/staging/prod
# would each instantiate it separately). It assumes:
#   - Two availability zones (EKS requires >= 2)
#   - One public subnet per AZ (ALB, NAT Gateway)
#   - One private subnet per AZ (EKS nodes, RDS, everything else)
#   - A single NAT Gateway in the first public subnet (cost-optimized)

variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'openbi-dev')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (must be >= 2 for EKS)"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required for EKS."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "Must provide exactly one public subnet CIDR per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "Must provide exactly one private subnet CIDR per availability zone."
  }
}

variable "single_nat_gateway" {
  description = "If true, provision a single NAT Gateway (cheaper, single point of failure). If false, one per AZ."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention for VPC Flow Logs in CloudWatch"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
