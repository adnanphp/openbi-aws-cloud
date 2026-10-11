# RDS module for OpenBI on AWS.
#
# Managed PostgreSQL to replace the local Postgres container.
#
# Design notes:
#   - Private subnets only; publicly_accessible = false
#   - Password managed by RDS, stored in Secrets Manager
#   - IAM database authentication enabled (no stored passwords in pods)
#   - Encrypted at rest with the default AWS-managed KMS key
#   - Parameter group tuned for analytical query patterns
#   - Automated backups with point-in-time recovery

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
# Security group
# ----------------------------------------------------------------------
# Allows PostgreSQL traffic (5432) from the cluster's baseline SG.
# No inbound from 0.0.0.0/0.

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "PostgreSQL access for the OpenBI RDS instance"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress_from_cluster" {
  count = length(var.allowed_security_group_ids) > 0 ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[0]
  security_group_id        = aws_security_group.rds.id
  description              = "PostgreSQL from the cluster baseline security group"
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "All outbound"
}

# ----------------------------------------------------------------------
# DB subnet group
# ----------------------------------------------------------------------
# RDS requires at least two subnets in different AZs, even for
# single-AZ instances. The subnet group can be used by other RDS
# resources in the future.

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Private subnets for OpenBI RDS"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-subnet-group"
  })
}

# ----------------------------------------------------------------------
# Parameter group
# ----------------------------------------------------------------------
# Tuned for analytical workloads. The local OpenBI Postgres uses
# defaults; on RDS, we tune a few settings.

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name_prefix}-pg16-"
  family      = "postgres16"
  description = "OpenBI tuned parameters for PostgreSQL 16"

  # Log slow queries. Logs go to CloudWatch via the RDS log exporter.
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000" # milliseconds
    apply_method = "immediate"
  }

  # Work memory: per-operation memory for sorting and hashing.
  # Larger values help analytical queries but reduce concurrency.
  parameter {
    name         = "work_mem"
    value        = "8192" # 8 MB
    apply_method = "immediate"
  }

  # Maintain more statistics columns for query planning.
  parameter {
    name         = "track_io_timing"
    value        = "1"
    apply_method = "immediate"
  }

  # Log all connections. Useful for auditing who accesses the DB.
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-pg16"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------------------------------
# RDS instance
# ----------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username

  # RDS generates a random password, stores it in Secrets Manager, and
  # handles rotation. Set manage_master_user_password = true and do not
  # provide a password.
  manage_master_user_password = true

  # IAM database authentication lets pods authenticate without a
  # password, using STS tokens derived from their IRSA role.
  iam_database_authentication_enabled = true

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.this.name

  # High availability (off by default in dev; variable-controlled)
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Monitoring
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null
  monitoring_interval                   = 0 # Enhanced Monitoring disabled (extra cost)

  # Log exports to CloudWatch
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Deletion behavior
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-postgres-final"

  # Apply changes immediately in dev; a production deployment would use
  # the maintenance window instead.
  apply_immediately = true

  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-postgres"
  })
}
