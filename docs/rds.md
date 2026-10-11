# RDS for PostgreSQL

Managed PostgreSQL replaces the local OpenBI Postgres container. The
data model is unchanged — the same star schema, the same `warehouse.*`
tables, the same dbt models. Only the underlying engine management
changes.

## Why RDS

A production data platform does not run PostgreSQL on an EC2 instance
it patches itself. It uses RDS (or Aurora, or Cloud SQL, or a similar
managed service) and lets AWS handle:

- OS patching
- PostgreSQL minor version upgrades
- Automated backups and point-in-time recovery
- Multi-AZ failover
- Storage autoscaling
- Performance monitoring

The trade-off is cost and reduced control over low-level settings.
For a data platform, that's the right trade.

## Instance design

| Setting | Value | Why |
| --- | --- | --- |
| Engine | PostgreSQL 16 | Matches the local Postgres 16 |
| Instance class | `db.t4g.micro` | Cheapest current-gen (ARM) |
| Storage | 20 GB gp3, autoscaling to 100 GB | Small baseline; grow on demand |
| Multi-AZ | No (variable) | Half the cost; single-AZ is fine for dev |
| Backup retention | 7 days | Point-in-time recovery window |
| Encryption | On (AWS-managed key) | Free, always on |
| Deletion protection | No (variable) | Allows `terraform destroy` in dev |
| Publicly accessible | No | Private subnets only |

## Parameter group

The parameter group (`openbi-dev-pg16`) tunes a few settings for
analytical workloads:

| Parameter | Value | Why |
| --- | --- | --- |
| `log_min_duration_statement` | 1000 ms | Log queries slower than 1 second |
| `work_mem` | 8 MB | More memory per sort/hash for analytical queries |
| `track_io_timing` | on | Better query plans; visible in Performance Insights |
| `log_connections` | on | Audit trail of who connects |
| `log_disconnections` | on | Audit trail of who disconnects |

These are conservative. A production deployment would tune `work_mem`
against actual concurrency and query patterns.

## Authentication

Two paths:

### 1. Password from Secrets Manager

RDS with `manage_master_user_password = true` generates a random
master password on creation, stores it in Secrets Manager, and rotates
it automatically. Applications retrieve the password at runtime.

This is the fallback path. Good for tools that don't support IAM
database authentication (psql, many BI tools, migration scripts).

### 2. IAM database authentication

Preferred for pods. The flow:
Pod (with IRSA role granting rds-db:connect)
│
│ boto3.rds.generate_db_auth_token()
▼
STS-signed token (valid 15 minutes)
│
│ used as the password
▼
PostgreSQL connection over TLS
│
│ RDS validates the token via IAM
▼
Connection established

text

**Requirements:**

1. IAM database authentication must be enabled on the instance (done)
2. The database user must be granted the `rds_iam` role:
   ```sql
   GRANT rds_iam TO openbiadmin;
The pod's IRSA role needs rds-db:connect permission for the
specific resource: arn:aws:rds-db:REGION:ACCOUNT:dbuser:RESOURCE_ID/USERNAME

Why IAM auth is preferred:

No long-lived password in a Kubernetes Secret

Tokens expire in 15 minutes — leaked tokens have a bounded blast radius

Access is governed by IRSA policy, which is version-controlled

No rotation to manage

Why password auth still matters:

Ad-hoc tools (psql, dbeaver) that don't speak IAM auth

Migration scripts that need to run once with elevated privileges

Fallback if IAM auth is broken

OpenBI supports both. The IRSA role and the connection code choose at
runtime.

Network
The instance lives in the private subnets from Phase A1. It has:

No public IP address

A security group allowing 5432 only from the EKS cluster's baseline
security group

The same subnet group as the cluster

To connect from a laptop for debugging, you need one of:

A bastion host

AWS Systems Manager Session Manager port forwarding

A temporary EC2 instance in the same VPC

Direct VPC access (VPN, Direct Connect)

None of these are set up in this repo (they're outside the scope of the
lab). The python/rds_connection.py script shows the code paths;
running it end-to-end requires one of the above.

Backups
Automated backups with a 7-day retention window. RDS stores backups in
S3 (managed by AWS, no bucket to configure). Point-in-time recovery is
available to any second within the retention window.

The backup window is Sunday 04:00 UTC. The maintenance window is Sunday
03:00 UTC (an hour before backups, so a maintenance event doesn't
interrupt a backup).

Monitoring
Performance Insights: enabled (7-day retention, free). Shows the
top SQL by database load, wait events, and per-user breakdown. This is
the single most useful RDS observability tool.

Enhanced Monitoring: disabled. Would add per-second OS-level
metrics to CloudWatch for ~$3–5/month. Not worth it for a lab.

CloudWatch Logs: postgresql and upgrade log exports. PostgreSQL
logs (including slow query logs from the parameter group) go to
CloudWatch. Visible in the console and queryable.

Cost
Item	Cost (eu-central-1)
db.t4g.micro single-AZ	~$13/month
20 GB gp3 storage	~$2.4/month
Backups (up to 100% of storage)	free
Performance Insights (7 days)	free
CloudWatch Logs	negligible at low volume
Total	~$15.50/month
Multi-AZ doubles the instance cost (~$26/month). Storage autoscaling
grows cost as data grows.

What maps to GCP
AWS	GCP
RDS for PostgreSQL	Cloud SQL for PostgreSQL
Instance class (db.t4g.micro)	Machine type (db-f1-micro)
Subnet group	Private Service Access
Parameter group	Database flags
Secrets Manager + manage_master_user_password	Secret Manager
IAM database authentication	IAM database authentication
Automated backups	Automated backups
Performance Insights	Query Insights
Multi-AZ	High availability (regional)
CloudWatch Logs export	Cloud Logging
What transfers directly:

Managed PostgreSQL as a service

Parameter tuning and the shape of the parameters

Automated backups and PITR

IAM-based authentication (both clouds support it)

Private networking

Performance monitoring tools

What does not transfer:

Parameter names (though many Postgres parameters are identical since
they're PostgreSQL parameters, not AWS-specific)

Secrets management integration (Secrets Manager vs. Secret Manager)

The exact instance class → machine type mapping

Failover mechanics

Verification status
Not verified against real AWS. The Terraform module is statically
validated, the Python code compiles, and the parameter choices match
AWS's published documentation. The module has not been applied to a
real AWS account. See verification.md.
