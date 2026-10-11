# ALB module for OpenBI on AWS.
#
# Provides:
#   - IRSA role for the AWS Load Balancer Controller
#   - Optional ACM certificate for HTTPS
#
# The ALB itself is NOT created here. The controller provisions ALBs on
# demand when Kubernetes Ingress resources are applied.

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
# IRSA role for the AWS Load Balancer Controller
# ----------------------------------------------------------------------
# The controller assumes this role via IRSA to create and manage ALBs.
# Trust policy scoped to the kube-system/aws-load-balancer-controller
# ServiceAccount.

data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.name_prefix}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb-controller-role"
  })
}

# AWS publishes the exact policy the controller needs. It's large
# (multiple statements covering ELB, EC2, WAF, Shield, ACM). The
# published policy is a moving target — AWS updates it as features are
# added — so attaching the managed policy is the correct pattern rather
# than inlining a snapshot.

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"
}

# ----------------------------------------------------------------------
# Optional ACM certificate for HTTPS
# ----------------------------------------------------------------------
# Only created when a domain name is provided. Validation via DNS
# requires a Route53 hosted zone in the same account.

resource "aws_acm_certificate" "this" {
  count = var.domain_name != "" ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = var.domain_name
  })
}

# Create Route53 validation records (only if a zone ID is provided).
# Without this, the certificate stays in "pending validation" and the
# user validates manually.

resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" && var.route53_zone_id != "" ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

resource "aws_acm_certificate_validation" "this" {
  count = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
