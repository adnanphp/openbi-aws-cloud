# IAM module for OpenBI on AWS.
#
# Creates the roles required by EKS.
#
# What this module provides:
#   - EKS cluster service role (assumed by the EKS control plane)
#   - EKS node group service role (assumed by EC2 worker nodes)
#   - Standard AWS-managed policy attachments for both
#   - A base IRSA role template for future service modules
#
# What this module does NOT provide:
#   - The OIDC provider for IRSA (owned by the EKS module in A4)
#   - Application-specific roles (each service module owns its own)
#   - RDS enhanced monitoring role (Phase A6)
#   - EBS CSI driver role (Phase A4)
#   - ALB Ingress Controller role (Phase A8)
#
# Design notes:
#   - No IAM users. Everything is roles + federation.
#   - No long-lived access keys. IRSA gives pods short-lived credentials.
#   - Trust policies live in iam/policies/*.json for readability.
#   - AWS-managed policies are used for A2. Custom least-privilege
#     policies come later when there are workloads to scope them to.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# ----------------------------------------------------------------------
# EKS cluster service role
# ----------------------------------------------------------------------
# The EKS control plane assumes this role to manage AWS resources on
# your behalf (ENIs, load balancers for the API server, etc.).

resource "aws_iam_role" "eks_cluster" {
  name = "${var.name_prefix}-eks-cluster-role"

  assume_role_policy = file("${path.module}/../../../iam/policies/eks-cluster-trust.json")

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ----------------------------------------------------------------------
# EKS node group service role
# ----------------------------------------------------------------------
# EC2 instances that form the Kubernetes worker nodes assume this role.
# The three attached policies cover:
#   - WorkerNodePolicy: allowing nodes to register with the cluster
#   - CNI_Policy: allowing the VPC CNI plugin to assign pod IPs
#   - EC2ContainerRegistryReadOnly: pulling images from ECR

resource "aws_iam_role" "eks_node" {
  name = "${var.name_prefix}-eks-node-role"

  assume_role_policy = file("${path.module}/../../../iam/policies/eks-node-trust.json")

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ----------------------------------------------------------------------
# Base IRSA role template
# ----------------------------------------------------------------------
# A placeholder role that future service modules will use as a pattern
# for pod-level roles. It has no policies attached; its purpose in A2
# is to document the structure of an IRSA trust policy (see
# iam/policies/irsa-trust.json).
#
# The role cannot be assumed successfully until:
#   1. The EKS cluster exists and has an OIDC provider registered in IAM
#   2. A Kubernetes ServiceAccount is annotated with this role's ARN
#   3. A pod using that ServiceAccount requests a token
#
# Both conditions are met in later phases.

resource "aws_iam_role" "irsa_template" {
  name = "${var.name_prefix}-irsa-template-role"

  assume_role_policy = file("${path.module}/../../../iam/policies/irsa-trust.json")

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-irsa-template-role"
    Purpose = "template"
  })
}
