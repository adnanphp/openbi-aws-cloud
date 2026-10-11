# Inputs for the EKS module.
#
# The module creates:
#   - An EKS cluster (control plane) with logging enabled
#   - The OIDC provider for IRSA
#   - Two managed node groups: on-demand (critical) + spot (workloads)
#   - Cluster add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver
#
# It depends on:
#   - The VPC module (subnets, security groups)
#   - The IAM module (cluster role, node role)

variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'openbi-dev')"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster runs"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the cluster and node groups"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "EKS requires at least two private subnets in different AZs."
  }
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role (from the iam module)"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node group IAM role (from the iam module)"
  type        = string
}

# ----------------------------------------------------------------------
# Endpoint access
# ----------------------------------------------------------------------

variable "endpoint_private_access" {
  description = "Enable the private API server endpoint (required)"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable the public API server endpoint (not needed if private is sufficient)"
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint (only used if endpoint_public_access is true)"
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------
# Control plane logging
# ----------------------------------------------------------------------

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types to send to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "Retention period for EKS control plane logs"
  type        = number
  default     = 7
}

# ----------------------------------------------------------------------
# Node groups
# ----------------------------------------------------------------------

variable "on_demand_instance_types" {
  description = "Instance types for the on-demand node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "on_demand_desired_size" {
  description = "Desired node count for the on-demand group"
  type        = number
  default     = 1
}

variable "on_demand_min_size" {
  description = "Minimum node count for the on-demand group"
  type        = number
  default     = 1
}

variable "on_demand_max_size" {
  description = "Maximum node count for the on-demand group"
  type        = number
  default     = 2
}

variable "spot_instance_types" {
  description = "Instance types for the spot node group"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "spot_desired_size" {
  description = "Desired node count for the spot group"
  type        = number
  default     = 1
}

variable "spot_min_size" {
  description = "Minimum node count for the spot group"
  type        = number
  default     = 0
}

variable "spot_max_size" {
  description = "Maximum node count for the spot group"
  type        = number
  default     = 3
}

variable "node_disk_size_gb" {
  description = "Root disk size in GB for worker nodes"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
