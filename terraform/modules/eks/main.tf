# EKS module for OpenBI on AWS.
#
# Creates an EKS cluster, two managed node groups (on-demand and spot),
# the OIDC provider for IRSA, and the standard cluster add-ons.
#
# Design notes:
#   - Managed node groups, not self-managed ASGs. AWS owns the node
#     lifecycle and AMI updates.
#   - Private API endpoint by default. Public access is opt-in.
#   - Control plane logs to CloudWatch (all five log types).
#   - OIDC provider is created here because it requires the cluster.
#   - EBS CSI driver add-on needs its own IRSA role; that role is
#     created in this module since it's specific to the driver.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------
# Cluster control plane
# ----------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [
    # The cluster role must exist before the cluster can be created.
    # The IAM module owns the role; this is a soft dependency enforced
    # by the caller's module wiring.
  ]
}

# ----------------------------------------------------------------------
# Control plane logs
# ----------------------------------------------------------------------
# EKS sends control plane logs to a CloudWatch log group named
# /aws/eks/<cluster-name>/cluster. We create the group explicitly so we
# can set retention; the cluster writes to it.

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-plane-logs"
  })
}

# ----------------------------------------------------------------------
# OIDC provider (enables IRSA)
# ----------------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

# ----------------------------------------------------------------------
# EBS CSI driver IRSA role
# ----------------------------------------------------------------------
# The EBS CSI driver runs as a DaemonSet in the cluster. It needs an IAM
# role to create/attach/detach EBS volumes when PersistentVolumeClaims
# are provisioned.
#
# The trust policy is scoped to a specific ServiceAccount:
#   kube-system/ebs-csi-controller-sa

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name_prefix}-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ebs-csi-driver-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ----------------------------------------------------------------------
# Cluster add-ons
# ----------------------------------------------------------------------
# The four standard add-ons. VPC CNI, CoreDNS, and kube-proxy are the
# defaults; the EBS CSI driver is required for PersistentVolumeClaims
# to provision EBS volumes.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpc-cni"
  })

  depends_on = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-coredns"
  })

  depends_on = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-kube-proxy"
  })

  depends_on = [aws_eks_node_group.on_demand]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ebs-csi"
  })

  depends_on = [
    aws_eks_node_group.on_demand,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

# ----------------------------------------------------------------------
# On-demand node group
# ----------------------------------------------------------------------
# One node by default. Runs critical system workloads.

resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-on-demand"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.on_demand_instance_types
  capacity_type   = "ON_DEMAND"
  disk_size       = var.node_disk_size_gb

  scaling_config {
    desired_size = var.on_demand_desired_size
    min_size     = var.on_demand_min_size
    max_size     = var.on_demand_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "critical"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-on-demand"
  })

  depends_on = [aws_eks_cluster.this]
}

# ----------------------------------------------------------------------
# Spot node group
# ----------------------------------------------------------------------
# Scales on demand. Runs user workloads. ~70% cheaper than on-demand
# but can be interrupted; safe for stateless services.

resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.spot_instance_types
  capacity_type   = "SPOT"
  disk_size       = var.node_disk_size_gb

  scaling_config {
    desired_size = var.spot_desired_size
    min_size     = var.spot_min_size
    max_size     = var.spot_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "workload"
  }

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-spot"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })

  depends_on = [aws_eks_cluster.this]
}
