# Secrets Manager module for OpenBI on AWS.
#
# Provides the IRSA role that External Secrets Operator assumes to read
# secrets from AWS Secrets Manager and materialize them as Kubernetes
# Secrets.
#
# The secret naming convention is <prefix>/<purpose>, e.g.:
#   openbi/dev/db
#   openbi/dev/redis
#   openbi/dev/api-keys
#
# The IAM policy is scoped to that prefix — the operator can only read
# secrets that start with it. That's least privilege.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  secrets_arn_prefix = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_path_prefix}"
}

# ----------------------------------------------------------------------
# IRSA trust policy
# ----------------------------------------------------------------------

data "aws_iam_policy_document" "eso_assume_role" {
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
      values   = ["system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.name_prefix}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-external-secrets-role"
  })
}

# ----------------------------------------------------------------------
# IAM policy scoped to the secret prefix
# ----------------------------------------------------------------------
# The operator can only read secrets under the configured prefix.
# KMS access is also scoped — it can decrypt via the AWS-managed
# secretsmanager key (which is what Secrets Manager uses by default).

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid    = "ReadSecretsUnderPrefix"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]

    resources = [
      "${local.secrets_arn_prefix}/*",
    ]
  }

  statement {
    sid    = "ListSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:ListSecrets",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DecryptWithSecretsManagerKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "${var.name_prefix}-external-secrets-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}
