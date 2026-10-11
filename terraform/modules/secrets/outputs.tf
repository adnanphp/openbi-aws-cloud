# Outputs from the Secrets Manager module.

output "eso_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator"
  value       = aws_iam_role.eso.arn
}

output "secret_path_prefix" {
  description = "The prefix under which OpenBI secrets should be stored"
  value       = var.secret_path_prefix
}

output "eso_policy_name" {
  description = "Name of the IAM policy attached to the ESO role"
  value       = aws_iam_role_policy.eso.name
}
