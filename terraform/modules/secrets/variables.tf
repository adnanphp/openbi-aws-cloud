# Inputs for the Secrets Manager module.
#
# Provides the mechanism for OpenBI services to retrieve secrets without
# storing them in Kubernetes manifests:
#
#   - The convention: secrets live under <prefix>/<env>/<purpose>
#   - An IRSA role that External Secrets Operator assumes
#   - The IAM policy scoping that role to the prefix

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "secret_path_prefix" {
  description = "Prefix for all secrets managed by this module (e.g. 'openbi/dev')"
  type        = string
  default     = "openbi/dev"
}

variable "cluster_name" {
  description = "EKS cluster name (used in the IRSA trust policy)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without the https:// prefix"
  type        = string
}

variable "external_secrets_namespace" {
  description = "Namespace of the External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "ServiceAccount name for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
