# Outputs from the EKS module.
#
# These are consumed by:
#   - Kubernetes configuration scripts (kubeconfig update)
#   - Future modules that need the OIDC provider for IRSA
#   - Documentation

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the cluster API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (used in IRSA trust policies)"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (used in IRSA trust policies)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider (without the https:// prefix)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "on_demand_node_group_name" {
  description = "Name of the on-demand node group"
  value       = aws_eks_node_group.on_demand.node_group_name
}

output "spot_node_group_name" {
  description = "Name of the spot node group"
  value       = aws_eks_node_group.spot.node_group_name
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver IRSA role"
  value       = aws_iam_role.ebs_csi.arn
}
