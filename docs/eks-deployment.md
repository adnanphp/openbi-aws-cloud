# EKS Deployment — End-to-End

How the pieces from Phases A1–A9 come together to run OpenBI on EKS.

## The full picture
AWS account
│
├── VPC (A1) 10.20.0.0/16
│ ├── 2 public subnets ALB, NAT
│ └── 2 private subnets EKS nodes, RDS
│
├── IAM (A2) EKS cluster role, node role
│
├── ECR (A3) openbi repository
│
├── EKS (A4) cluster + on-demand + spot node groups
│ ├── OIDC provider enables IRSA
│ ├── cluster add-ons VPC CNI, CoreDNS, kube-proxy, EBS CSI
│ └── EKS workloads:
│ ├── Cluster Autoscaler (kubernetes/cluster-autoscaler/)
│ ├── ALB Controller (kubernetes/aws-load-balancer-controller/)
│ ├── External Secrets (kubernetes/external-secrets/)
│ ├── Fluent Bit (kubernetes/cluster-addons/)
│ ├── CloudWatch agent (kubernetes/cluster-addons/)
│ └── OpenBI app:
│ ├── FastAPI (kubernetes/openbi-app/)
│ └── Superset (kubernetes/openbi-app/)
│
├── S3 (A5) raw / processed / models buckets
│
├── RDS (A6) PostgreSQL instance
│
├── SQS (A7) events + DLQ
│
├── ALB (A8) provisioned by the controller
│
├── CloudWatch (A9) log groups, dashboard, alarms
│
└── Secrets Manager (A9) secret store + ESO IRSA

text

## The pod-to-AWS path

When a FastAPI pod starts:
Kubelet pulls the image from ECR
Uses the node's IAM role (AmazonEC2ContainerRegistryReadOnly)

Pod schedules on a node in a private subnet

Pod has a ServiceAccount (default for now)

If it needs AWS access, an IRSA role is attached

FastAPI uses the ClusterSecretStore path via ESO instead

ESO has already created the openbi-db-credentials Secret:

ESO pod assumes its IRSA role

Reads openbi/dev/db from Secrets Manager

Creates the Kubernetes Secret in the openbi namespace

FastAPI pod mounts the Kubernetes Secret as env vars:

DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME

FastAPI opens a TLS connection to RDS:

RDS is in the same VPC, in private subnets

Connection goes through the RDS security group

When FastAPI reads/writes objects:

It calls the S3 API

Traffic goes through the VPC NAT Gateway to S3

Or via a VPC endpoint if configured (not in this repo)

When FastAPI emits logs:

stdout is captured by the container runtime

Fluent Bit on the same node reads /var/log/pods/

Fluent Bit batches and ships to CloudWatch Logs

text

## What's requested from AWS

The FastAPI pod requires:

| Resource | From | How |
| --- | --- | --- |
| Container image | ECR | Node role grants pull |
| Database | RDS | Secret via ESO |
| Object storage | S3 | Env vars from ConfigMap + IAM permissions (to be added via IRSA in a future phase) |
| Log destination | CloudWatch Logs | Fluent Bit DaemonSet |

Note: **FastAPI does not currently have an IRSA role** for direct S3/SQS access. The cluster has the ESO role (for secrets), but the FastAPI pod itself uses the node role for AWS API calls. A production deployment would give FastAPI its own IRSA role scoped to the specific buckets and queues it uses. That's documented as a future enhancement.

## Applying the whole stack

```bash
# 1. Terraform (creates VPC, IAM, ECR, EKS, S3, RDS, SQS, ALB role,
#    CloudWatch, Secrets Manager)
cd terraform/environments/dev
terraform init
terraform apply

# 2. Update kubeconfig
aws eks update-kubeconfig --name openbi-dev --region eu-central-1

# 3. Install cluster controllers via Helm
#    (see the README in each kubernetes/<controller>/ directory)

# 4. Apply namespaces and add-ons
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/cluster-addons/

# 5. Apply ClusterSecretStore and OpenBI manifests
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml
kubectl apply -k kubernetes/openbi-app/overlays/dev
Order dependencies
text
Terraform apply
    │
    ├── VPC must exist before EKS
    ├── IAM roles must exist before EKS
    ├── EKS must exist before kubeconfig
    │
    ▼
kubectl apply
    │
    ├── Namespaces must exist before app
    ├── Controllers must be installed before Ingress/ExternalSecret
    ├── ClusterSecretStore must exist before ExternalSecret
    │
    ▼
OpenBI workloads running
Terraform handles its own dependencies via resource references. For
Kubernetes, apply order matters — the manifest directory structure
mirrors that order.

What's not in A10
FastAPI's own IRSA role. Currently the pod uses the node role.
Future work: create a role scoped to specific S3 buckets and SQS
queues.

Redis / ElastiCache. Documented as a gap; Superset works without
it, but slower.

Kafka / MSK. Documented as a gap; OpenBI's streaming tier isn't
reproduced in this deployment.

OpenFaaS / Lambda. The local serverless layer isn't reproduced.

HorizontalPodAutoscaler (HPA). FastAPI scales horizontally based
on CPU. Documented as future work.

PodDisruptionBudgets (PDB). For safe node drains.

NetworkPolicies. For pod-to-pod isolation.

Each is documented in its respective future phase or as an explicit gap.

Verification
After applying everything:

bash
# Everything running?
kubectl -n openbi get pods
kubectl -n openbi get ingress
kubectl -n openbi get externalsecret

# Secrets synced?
kubectl -n openbi get secret openbi-db-credentials

# Reachable via the ALB?
kubectl -n openbi get ingress openbi-api

# Logs flowing?
aws logs tail /aws/openbi/fastapi --follow
What maps to GCP
The same architecture on GCP:

AWS	GCP
EKS	GKE
ALB Controller	GKE Ingress (built-in)
External Secrets Operator	External Secrets Operator (same)
CloudWatch agent	Ops Agent
Fluent Bit	Fluent Bit (same)
IRSA	Workload Identity
CloudWatch Logs	Cloud Logging
Cluster Autoscaler	GKE Autopilot / Node Auto-Provisioning
What transfers directly:

The Kubernetes manifests (identical)

External Secrets Operator

Fluent Bit configuration (mostly)

The concept of "controllers do the cloud integration"

What does not transfer:

IRSA (Workload Identity is the GCP mechanism)

The ALB Controller (GKE has this built in)

CloudWatch-specific configuration

The specific IAM role structure

Verification status
Not verified against real AWS. All Terraform modules and Kubernetes
manifests are statically validated. The complete deployment has not
been applied to a real AWS account. See verification.md.
