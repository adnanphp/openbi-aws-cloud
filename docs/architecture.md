# Architecture

OpenBI on AWS targets a managed-services architecture: EKS for compute,
RDS for Postgres, S3 for object storage, SQS for messaging, ALB for
ingress. The goal is to run the same OpenBI workload that currently runs
on Kind, but backed by AWS-native services.

## Target architecture
Internet
│
▼
┌──────────────────┐
│ Application │ ← AWS-managed, provisioned via ALB
│ Load Balancer │ Ingress Controller
└────────┬─────────┘
│
▼
┌──────────────────────────────┐
│ Amazon EKS Cluster │
│ │
│ ┌─────────┐ ┌───────────┐ │
│ │ FastAPI │ │ Superset │ │
│ └────┬────┘ └─────┬─────┘ │
│ │ │ │
│ ┌────▼────┐ ┌─────▼─────┐ │
│ │ OpenFaaS│ │ Traefik │ │
│ └─────────┘ └───────────┘ │
└──────┬──────────────────────┘
│
┌────────┼──────────┬──────────┐
▼ ▼ ▼ ▼
┌──────┐ ┌────┐ ┌──────────┐ ┌────────┐
│ RDS │ │ S3 │ │ SQS │ │ Cloud │
│ PG │ │ │ │ (+DLQ) │ │ Watch │
└──────┘ └────┘ └──────────┘ └────────┘
│ │ │ │
└────────┴──────────┴──────────┘
│
┌──────▼──────┐
│ Secrets │
│ Manager │
└─────────────┘

text

## Design principles

1. **No public subnets for workloads.** EKS nodes, RDS, and all internal
   services live in private subnets. Only the ALB and NAT Gateway sit
   in public subnets.
2. **Two availability zones minimum.** EKS requires this. RDS Multi-AZ
   requires it too.
3. **Managed services over self-hosted wherever possible.** RDS instead
   of Postgres on EC2. S3 instead of MinIO on EC2. This is the
   difference between running Kubernetes and *using* AWS.
4. **IAM least privilege, per service.** Each service gets its own IAM
   role with only the permissions it needs. No shared roles.
5. **All secrets in Secrets Manager.** Nothing sensitive in Kubernetes
   Secrets or environment variables.
6. **Logs to CloudWatch, metrics to CloudWatch.** Do not fight the
   platform; use what AWS provides.

## Phase A1 — VPC

Phase A1 establishes the network foundation:

- **VPC** with CIDR `10.20.0.0/16`, DNS hostnames and resolution enabled
  (required for EKS private endpoint)
- **Two public subnets** (`10.20.0.0/24`, `10.20.1.0/24`) across two AZs
  — used by the Application Load Balancer and NAT Gateway
- **Two private subnets** (`10.20.10.0/24`, `10.20.11.0/24`) across the
  same two AZs — used by EKS nodes, RDS, and all workloads
- **Internet Gateway** for public subnet egress
- **Single NAT Gateway** (default) for private subnet egress. Switch to
  one-per-AZ via `var.single_nat_gateway = false` for HA.
- **Baseline security group** for intra-VPC traffic; per-service
  security groups come with each service module.
- **VPC Flow Logs** to CloudWatch (7-day retention) for observability.

## Why these choices

### Why two AZs and not one?

EKS requires at least two subnets in two different AZs. RDS Multi-AZ
also requires two. Designing for two from the start avoids painful
refactoring later. A single-AZ VPC cannot host a production-grade EKS
cluster.

### Why separate public and private subnets?

Resources that need a public IP (ALB, NAT Gateway) go in public
subnets. Resources that don't (EKS nodes, RDS, all internal services)
go in private subnets, where they can reach the internet only via NAT
(outbound) and cannot be reached inbound from the internet at all.

### Why a single NAT Gateway by default?

A NAT Gateway costs ~$32/month in `eu-central-1`. Two of them (one per
AZ, the HA configuration) cost ~$64/month. For a dev environment, the
single NAT is fine — a NAT Gateway failure is rare, and the cost
savings matter. Production deployments should set
`single_nat_gateway = false`.

### Why VPC Flow Logs on by default?

Flow logs are the first thing you need when debugging "why can't this
pod reach that service." They capture every accepted and rejected
flow with source, destination, port, and protocol. For a lab where the
cost is negligible, having them on from day one is worth it.

### Why no security groups for specific services here?

Each service (EKS nodes, RDS, ALB, etc.) will define its own security
group in its own module. This keeps the VPC module focused on the
network foundation and makes it easy to reason about who can talk to
whom by reading each service's module. The only security group here
is the baseline SG that provides an anchor for cross-service
communication.

## What is not yet in this repo

The following are planned but not yet implemented:

- **EKS** — cluster, managed node groups, IRSA, autoscaler
- **ECR** — container image registry
- **RDS** — PostgreSQL instance, parameter groups, backups
- **S3** — buckets, lifecycle, versioning, encryption
- **SQS** — queues and dead-letter queues
- **ALB** — Application Load Balancer + Ingress Controller
- **IAM** — least-privilege roles per service, IRSA roles
- **CloudWatch** — log groups per service, alarms, dashboards
- **Secrets Manager** — secret storage and rotation
- **Kubernetes** — OpenBI manifests adapted for EKS
- **Deployment** — build, push, and apply scripts

See `ROADMAP.md` for the sequencing.

## Verification status

See `verification.md`. Everything in this repo is **statically
validated** (terraform validate, tflint, fmt) but not applied against
a real AWS account. The verification status is explicit in that
document because it matters.
