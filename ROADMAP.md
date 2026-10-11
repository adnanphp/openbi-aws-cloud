# OpenBI on AWS — Roadmap

Phases are sequential. Each phase ends with:
- Working Terraform (or manifests)
- Static validation passing in CI
- Documentation
- A commit

## Phase A1 — VPC (current)

**Scope:** VPC, subnets, internet gateway, NAT gateway(s), route tables,
baseline security group, VPC Flow Logs.

**Deliverables:**
- `terraform/modules/vpc/` — the module
- `terraform/environments/dev/` — the composition
- `docs/architecture.md` — the target architecture
- `docs/verification.md` — what's verified
- `scripts/validate.sh` — offline validation
- `.github/workflows/validate.yml` — CI

**Not in scope:** everything else.

---

## Phase A2 — IAM foundation ✅

**Scope:** The IAM roles and policies that later phases will attach to
services.

- Service-linked roles for EKS, RDS, etc.
- The EKS cluster role and node group role
- IRSA (IAM Roles for Service Accounts) setup with OIDC provider
- Least-privilege policies per service

**Deliverables:** `terraform/modules/iam/`, `iam/policies/*.json`,
`iam/README.md`.

---

## Phase A3 — ECR (next)

**Scope:** Container image registry.

- ECR repository
- Lifecycle policy (keep last 10 images)
- Repository policy (no public pull)

**Deliverables:** `terraform/modules/ecr/`,
`scripts/build-and-push.sh`.

---

## Phase A4 — EKS ✅

**Scope:** The Kubernetes cluster.

- EKS cluster (private endpoint)
- Managed node groups (2–3 nodes, mixed on-demand/spot)
- Add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver
- Cluster autoscaler
- OIDC provider for IRSA

**Deliverables:** `terraform/modules/eks/`,
`kubernetes/openbi-app/`.

---

## Phase A5 — S3 ✅

**Scope:** Object storage to replace MinIO.

- Buckets: `openbi-raw`, `openbi-processed`, `openbi-models`
- Versioning, encryption (SSE-KMS), lifecycle policies
- Bucket policies
- Event notifications to SQS

**Deliverables:** `terraform/modules/s3/`, `python/s3_operations.py`.

---

## Phase A6 — RDS for PostgreSQL ✅

**Scope:** Managed Postgres to replace the local Postgres.

- RDS PostgreSQL 16
- DB subnet group across private subnets
- Parameter group tuned for analytical queries
- Automated backups (7-day retention)
- Multi-AZ for production (single-AZ for dev)
- IAM database authentication

**Deliverables:** `terraform/modules/rds/`, `python/rds_connection.py`.

---

## Phase A7 — SQS ✅

**Scope:** Messaging to complement Kafka.

- Queues: `openbi-events`, `openbi-events-dlq`
- DLQ with redrive policy
- Queue policies for IRSA roles

**Deliverables:** `terraform/modules/sqs/`, `python/sqs_operations.py`.

---

## Phase A8 — ALB + Ingress ✅

**Scope:** External access.

- Application Load Balancer
- AWS Load Balancer Controller for Kubernetes
- ACM certificate (optional; requires domain)
- Route53 records (optional)

**Deliverables:** `terraform/modules/alb/`,
`kubernetes/ingress/`.

---

## Phase A9 — CloudWatch + Secrets Manager ✅

**Scope:** Observability and secrets.

- CloudWatch log groups per service
- CloudWatch alarms (EKS node health, RDS connections, ALB 5xx)
- CloudWatch dashboards as code
- Secrets Manager secrets for DB credentials, API keys
- External Secrets Operator in Kubernetes

**Deliverables:** `terraform/modules/cloudwatch/`,
`terraform/modules/secrets/`, `kubernetes/external-secrets/`.

---

## Phase A10 — Kubernetes manifests ✅

**Scope:** Adapt the OpenBI manifests for EKS.

- Namespaces
- Deployments, Services (referencing ECR images)
- ConfigMaps, Secrets (via External Secrets Operator)
- IngressRoutes (via ALB Ingress Controller)
- HorizontalPodAutoscalers

**Deliverables:** everything under `kubernetes/`.

---

## Phase A11 — Deployment scripts + documentation ✅

**Scope:** The end-to-end story.

- `scripts/deploy.sh` — full deployment
- `scripts/teardown.sh` — full cleanup
- `docs/deployment.md` — step by step, with cost warnings
- `docs/teardown.md` — safe destruction
- `docs/cost-estimate.md` — what a full deployment would cost
- `docs/troubleshooting.md` — common failure modes

**Deliverables:** as listed.

---

## Phase A12 — Optional live validation (next)

**Scope:** If you ever have an AWS account and budget.

- `terraform apply` against dev
- Deploy OpenBI
- Run integration tests
- Capture results in `docs/verification.md`
- Destroy everything
- Confirm no residual cost

**Deliverables:** screenshots and an updated verification doc.

---

## After AWS: GCP

A separate repo (`openbi-gcp-cloud`) mirrors this structure with GCP
resources. The AWS work becomes the reference pattern; the GCP work
becomes the translation exercise.
