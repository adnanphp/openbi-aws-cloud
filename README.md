# OpenBI on AWS

> AWS deployment architecture for [OpenBI](https://github.com/adnanphp/openbi) — the same data platform that runs locally, deployed against AWS managed services.

[![Validate](https://github.com/adnanphp/openbi-aws-cloud/actions/workflows/validate.yml/badge.svg)](https://github.com/adnanphp/openbi-aws-cloud/actions/workflows/validate.yml)

## ⚠️ Verification status

This repository contains a **complete AWS deployment configuration** for OpenBI. It has been **statically validated** but **not deployed to a live AWS account**.

| Layer | Status |
|---|---|
| Terraform syntax + schema | ✅ `terraform validate` passes |
| Terraform formatting | ✅ `terraform fmt -check` passes |
| Terraform linting | ✅ `tflint` passes |
| Kubernetes manifests | 📋 planned |
| IAM trust policies | ✅ JSON validated; not applied |
| End-to-end deployment | ❌ not verified — requires AWS account |

See [docs/verification.md](docs/verification.md) for the full breakdown. The status is documented explicitly because it matters: infrastructure code that has not been applied is a different artifact from infrastructure code that has.

## What this repo is

The [OpenBI platform](https://github.com/adnanphp/openbi) runs locally on Kubernetes (Kind) with self-hosted services: MinIO, Redis, Kafka, Loki, OpenFaaS, Superset, and more. It works, but it runs on your laptop.

**This repository maps each local component to its AWS counterpart:**

| Local (OpenBI) | AWS |
|---|---|
| Kind cluster | **Amazon EKS** |
| Traefik ingress | **Application Load Balancer** + Ingress Controller |
| MinIO | **Amazon S3** |
| Redis | **ElastiCache for Redis** |
| Kafka | **Amazon MSK** (or SQS for simpler workloads) |
| PostgreSQL | **Amazon RDS for PostgreSQL** |
| LocalStack | *(replaced by real AWS)* |
| OpenFaaS | **AWS Lambda** |
| Loki + Promtail | **CloudWatch Logs** |
| Prometheus + Grafana | **Amazon Managed Prometheus** + **Managed Grafana** |
| Docker images | **Amazon ECR** |
| Kubernetes Secrets | **AWS Secrets Manager** |

The mapping is documented in detail in the companion [cloud-mapping document](https://github.com/adnanphp/openbi/blob/main/docs/cloud-mapping.md).

## What's in this repo
openbi-aws-cloud/
├── README.md ← this file
├── ROADMAP.md ← phase plan
├── docs/
│ ├── architecture.md ← target AWS architecture + design decisions
│ ├── verification.md ← what's verified and what isn't
│ └── (more coming)
├── terraform/
│ ├── modules/ ← reusable modules
│ │ └── vpc/ ← Phase A1 (current)
│ └── environments/
│ └── dev/ ← dev composition
├── kubernetes/ ← OpenBI manifests for EKS (planned)
├── iam/ ← IAM policies (planned)
├── scripts/
│ └── validate.sh ← static validation
├── python/ ← boto3 examples (planned)
└── .github/workflows/
└── validate.yml ← CI: format + validate on every push

text

## Status — Phase A1 (in progress)

Phase A1 delivers the VPC foundation:

- ✅ VPC module (`terraform/modules/vpc/`)
- ✅ Dev environment composition (`terraform/environments/dev/`)
- ✅ Static validation (`.github/workflows/validate.yml`)
- ✅ Architecture documentation
- ⏳ (next) EKS, ECR, RDS, S3, SQS, ALB, IAM, CloudWatch

See [ROADMAP.md](ROADMAP.md) for the full plan.

## Running the validation

```bash
./scripts/validate.sh
No AWS account needed. Requires Terraform ≥ 1.5.0 and (optionally) tflint.

Deploying to a real AWS account
Not recommended yet. Phase A1 only deploys a VPC and NAT Gateway. The full deployment guide comes with the final phase. When it's ready, the commands will be in docs/deployment.md — with cost warnings, cleanup steps, and a full inventory of what gets created.

Cost estimate
If you were to apply this VPC to a real AWS account (phase A1 only):

Resource	Monthly cost
VPC, subnets, route tables, IGW, security groups	$0
1 NAT Gateway (eu-central-1)	~$32
VPC Flow Logs (low volume)	<$1
Total	~$33/month
A full OpenBI deployment would add EKS control plane (~$73), worker nodes, RDS, ALB, and storage. See docs/cost-estimate.md (to be written).

Related repositories
openbi — the platform (v3.0.0)

openbi-desktop — native Linux client (v0.1.0)

openbi-labs — deep-dive explorations

openbi-gcp-cloud (planned) — GCP equivalent

License
MIT

---

## Status — Phase A2 (current)

Phase A2 delivers the IAM foundation:

- ✅ EKS cluster service role + policy attachments
- ✅ EKS node group service role + policy attachments
- ✅ Base IRSA template role
- ✅ Trust policies as documented JSON files (`iam/policies/`)
- ✅ `docs/iam-overview.md`
- ✅ JSON validation in `scripts/validate.sh`
- ⏳ (next) ECR, EKS, S3, RDS, SQS, ALB, CloudWatch

---

*Earlier: Phase A1 delivered the VPC (see [ROADMAP.md](ROADMAP.md)).*

## Continuous integration

Every push to `main` runs offline validation on the Terraform and JSON
policies. The workflow needs no AWS credentials and creates no
resources.

![Green CI runs](docs/images/workflows_01.png)

---

## Status — Phase A4 (current)

Phase A4 delivers the EKS cluster:

- ✅ EKS cluster (private endpoint, all control plane logs to CloudWatch)
- ✅ Two managed node groups: on-demand (critical) + spot (workloads)
- ✅ OIDC provider for IRSA
- ✅ EBS CSI driver IRSA role + cluster add-on
- ✅ Cluster add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI
- ✅ Kubernetes manifest directory structure
- ✅ `docs/eks.md`

See [ROADMAP.md](ROADMAP.md) for the full plan.

---

*Earlier phases: A1 (VPC), A2 (IAM), A3 (ECR).*

---

## Status — Phase A5 (current)

Phase A5 delivers S3 object storage:

- ✅ Three buckets: raw (versioning on), processed, models (versioning on)
- ✅ Encryption (SSE-S3 default; SSE-KMS optional)
- ✅ Lifecycle policies tuned per bucket
- ✅ Public access blocked at the bucket level
- ✅ Bucket policies denying non-account access and insecure transport
- ✅ `python/s3_operations.py` — boto3 examples
- ✅ `docs/s3.md`

---

*Earlier phases: A1 (VPC), A2 (IAM), A3 (ECR), A4 (EKS).*

---

## Status — Phase A6 (current)

Phase A6 delivers RDS for PostgreSQL:

- ✅ PostgreSQL 16 on `db.t4g.micro` (ARM), 20 GB gp3
- ✅ Private subnets only; no public access
- ✅ Parameter group tuned for analytical workloads
- ✅ Secrets Manager-managed master password (RDS-managed rotation)
- ✅ IAM database authentication enabled
- ✅ Automated backups (7-day retention) + PITR
- ✅ Performance Insights (7-day retention, free)
- ✅ CloudWatch Logs export for postgresql + upgrade logs
- ✅ `python/rds_connection.py` (both auth paths)
- ✅ `docs/rds.md`

---

*Earlier phases: A1 (VPC), A2 (IAM), A3 (ECR), A4 (EKS), A5 (S3).*

---

## Status — Phase A7 (current)

Phase A7 delivers SQS messaging:

- ✅ Standard events queue + dead-letter queue
- ✅ Redrive policy (max 3 receives → DLQ)
- ✅ Long polling enabled by default (20s)
- ✅ SSE-SQS encryption
- ✅ Queue policies denying non-account access and insecure transport
- ✅ `python/sqs_operations.py` — send, long-poll receive, DLQ flow
- ✅ `docs/sqs.md`

---

*Earlier phases: A1 (VPC), A2 (IAM), A3 (ECR), A4 (EKS), A5 (S3), A6 (RDS).*
