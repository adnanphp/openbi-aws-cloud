# S3 module for OpenBI on AWS.
#
# Creates three buckets that mirror the OpenBI data lifecycle. Each
# bucket gets:
#   - Encryption at rest (SSE-S3 by default, SSE-KMS optional)
#   - Public access blocked (all four flags)
#   - A lifecycle policy matched to its role
#   - A bucket policy denying non-account access
#
# What this module does NOT provide:
#   - IAM policies granting pods access (those are IRSA roles created
#     per service module)
#   - Event notifications (added in a later phase, when there's a
#     consumer)

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------
# Raw bucket
# ----------------------------------------------------------------------
# Landing zone for source data. Versioning on so we never lose the
# original. Lifecycle: IA at 30d, Glacier at 90d, expire at 365d.

resource "aws_s3_bucket" "raw" {
  bucket = "${var.raw_bucket_name}-${var.bucket_suffix}"

  tags = merge(var.tags, {
    Name    = "${var.raw_bucket_name}-${var.bucket_suffix}"
    Purpose = "raw-data"
  })
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_type
      kms_master_key_id = var.encryption_type == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.encryption_type == "aws:kms"
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = var.raw_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.raw_transition_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.raw_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "raw" {
  bucket = aws_s3_bucket.raw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonAccountAccess"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Processed bucket
# ----------------------------------------------------------------------
# Cleaned/derived data. Versioning off (regeneratable). Lifecycle:
# expire after 90 days.

resource "aws_s3_bucket" "processed" {
  bucket = "${var.processed_bucket_name}-${var.bucket_suffix}"

  tags = merge(var.tags, {
    Name    = "${var.processed_bucket_name}-${var.bucket_suffix}"
    Purpose = "processed-data"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_type
      kms_master_key_id = var.encryption_type == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.encryption_type == "aws:kms"
  }
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = var.processed_expiration_days
    }
  }
}

resource "aws_s3_bucket_policy" "processed" {
  bucket = aws_s3_bucket.processed.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonAccountAccess"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.processed.arn,
          "${aws_s3_bucket.processed.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Models bucket
# ----------------------------------------------------------------------
# ML artifacts. Versioning on (model history matters). Lifecycle: keep
# non-current versions for 90 days.

resource "aws_s3_bucket" "models" {
  bucket = "${var.models_bucket_name}-${var.bucket_suffix}"

  tags = merge(var.tags, {
    Name    = "${var.models_bucket_name}-${var.bucket_suffix}"
    Purpose = "ml-models"
  })
}

resource "aws_s3_bucket_versioning" "models" {
  bucket = aws_s3_bucket.models.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.models.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_type
      kms_master_key_id = var.encryption_type == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.encryption_type == "aws:kms"
  }
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket = aws_s3_bucket.models.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.models_noncurrent_expiration_days
    }
  }
}

resource "aws_s3_bucket_policy" "models" {
  bucket = aws_s3_bucket.models.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonAccountAccess"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.models.arn,
          "${aws_s3_bucket.models.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.models.arn,
          "${aws_s3_bucket.models.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
