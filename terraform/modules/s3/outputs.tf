# Outputs from the S3 module.
#
# The bucket names and ARNs are consumed by:
#   - IRSA policies that grant pods access to specific buckets
#   - Application configuration (env vars pointing at the bucket names)

output "raw_bucket_name" {
  description = "Name of the raw data bucket"
  value       = aws_s3_bucket.raw.bucket
}

output "raw_bucket_arn" {
  description = "ARN of the raw data bucket"
  value       = aws_s3_bucket.raw.arn
}

output "processed_bucket_name" {
  description = "Name of the processed data bucket"
  value       = aws_s3_bucket.processed.bucket
}

output "processed_bucket_arn" {
  description = "ARN of the processed data bucket"
  value       = aws_s3_bucket.processed.arn
}

output "models_bucket_name" {
  description = "Name of the models bucket"
  value       = aws_s3_bucket.models.bucket
}

output "models_bucket_arn" {
  description = "ARN of the models bucket"
  value       = aws_s3_bucket.models.arn
}
