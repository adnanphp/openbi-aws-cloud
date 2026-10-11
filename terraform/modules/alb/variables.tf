# Inputs for the ALB module.
#
# The ALB itself is created by the AWS Load Balancer Controller when a
# Kubernetes Ingress is applied — not by Terraform. This module creates
# the IAM role the controller needs (via IRSA), and optionally an ACM
# certificate for HTTPS.
#
# What this module provides:
#   - An IRSA role for the AWS Load Balancer Controller
#   - The AWS-published AWSLoadBalancerControllerIAMPolicy attached
#   - Optional ACM certificate (only when a domain name is provided)

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used in the IRSA trust policy)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider (from the eks module)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the cluster's OIDC provider, without the https:// prefix (from the eks module)"
  type        = string
}

# ----------------------------------------------------------------------
# Optional HTTPS
# ----------------------------------------------------------------------
# ACM certificates require a domain name you control. Leave empty for
# HTTP-only (fine for a lab). Set to enable HTTPS.

variable "domain_name" {
  description = "Primary domain name for the ACM certificate (empty = no certificate)"
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "Additional SANs for the certificate"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS validation (required if domain_name is set and you want automatic validation)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
