# Inputs for the IAM module.
#
# The module creates the roles needed by the EKS cluster and its nodes.
# It does not create any application-level roles — those come with each
# service module.

variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'openbi-dev')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
