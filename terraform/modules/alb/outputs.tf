# Outputs from the ALB module.

output "controller_role_arn" {
  description = "ARN of the IRSA role for the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "controller_role_name" {
  description = "Name of the IRSA role"
  value       = aws_iam_role.alb_controller.name
}

output "certificate_arn" {
  description = "ARN of the ACM certificate (null if no domain configured)"
  value       = var.domain_name != "" ? aws_acm_certificate.this[0].arn : null
}
