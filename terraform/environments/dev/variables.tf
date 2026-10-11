variable "aws_region" {
  description = "AWS region for the dev environment"
  type        = string
  default     = "eu-central-1"
}

variable "bucket_suffix" {
  description = "Globally unique suffix for S3 bucket names (typically the AWS account ID)"
  type        = string
  default     = "REPLACE-WITH-AWS-ACCOUNT-ID"
}
