# Outputs from the IAM module.
#
# The EKS module will consume these to attach the roles to the cluster
# and node groups.

output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_cluster_role_name" {
  description = "Name of the EKS cluster service role"
  value       = aws_iam_role.eks_cluster.name
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node group service role"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "Name of the EKS node group service role"
  value       = aws_iam_role.eks_node.name
}

output "irsa_template_role_arn" {
  description = "ARN of the base IRSA template role"
  value       = aws_iam_role.irsa_template.arn
}
