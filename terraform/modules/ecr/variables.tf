# Inputs for the ECR module.
#
# Creates a single ECR repository for all OpenBI container images.
# Images are distinguished by tag (e.g. fastapi-0.1.0, superset-3.1.3).

variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'openbi-dev')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name_prefix))
    error_message = "name_prefix must be 3-32 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "openbi"
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents tag overwrites; MUTABLE allows them"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

variable "keep_last_tagged" {
  description = "Number of tagged images to keep per image name"
  type        = number
  default     = 10
}

variable "delete_untagged_after_days" {
  description = "Days after which untagged images are deleted"
  type        = number
  default     = 7
}

variable "force_delete" {
  description = "Allow deletion of the repository even if it contains images (dev convenience)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
