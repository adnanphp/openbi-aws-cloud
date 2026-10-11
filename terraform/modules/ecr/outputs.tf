# Outputs from the ECR module.
#
# The consuming scripts and future K8s manifests need the repository
# URL to know where to push/pull images.

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Full URL of the ECR repository (used for docker push/pull)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "AWS account ID that owns the registry"
  value       = aws_ecr_repository.this.registry_id
}
