# OpenBI Application Manifests

Kustomize manifests for running OpenBI on EKS.

## What's here vs. what's not

In EKS, several services that run as containers locally are now managed
services:

| Local (Kind) | EKS |
| --- | --- |
| Postgres (container) | **RDS** (external, from A6) |
| MinIO (container) | **S3** (external, from A5) |
| Kafka (container) | *(not included — could be MSK or SQS)* |
| Redis (container) | *(not included — could be ElastiCache)* |
| LocalStack (container) | **real AWS** |
| OpenFaaS (Helm) | *(not included — could be Lambda)* |
| Loki + Promtail (Helm) | **CloudWatch Logs** (external, from A9) |
| Prometheus (container) | **CloudWatch Metrics** (external, from A9) |

What remains as Kubernetes workloads:

- **FastAPI** — 2 replicas, connects to RDS and S3
- **Superset** — 1 replica, connects to RDS (separate database)

Everything else is either a managed AWS service or provided by the
cluster add-ons.

## Applying

```bash
# Base (default)
kubectl apply -k kubernetes/openbi-app/base

# Dev overlay (1 FastAPI replica)
kubectl apply -k kubernetes/openbi-app/overlays/dev
Before applying
Several placeholders must be replaced with real values:

Placeholder	Where	Replace with
REPLACE-WITH-ECR-URL/openbi:fastapi-latest	base/fastapi-deployment.yaml	The ECR repository URL from Terraform output
openbi-raw-REPLACE	base/configmap.yaml	The bucket name from Terraform output
openbi-events-REPLACE in SQS URL	base/configmap.yaml	The queue URL from Terraform output
After replacing, commit the changes (or use kustomize edit set image
for the image reference).

Prerequisites
The openbi namespace exists (kubernetes/namespaces/)

The aws-secrets-manager ClusterSecretStore exists
(kubernetes/external-secrets/)

The External Secrets Operator is running

The AWS Load Balancer Controller is running

The secrets openbi/dev/db and openbi/dev/superset exist in
Secrets Manager

Verifying
bash
kubectl -n openbi get pods
kubectl -n openbi get ingress
kubectl -n openbi get externalsecret
The ExternalSecret should show STATUS=SecretSynced. If not, check:

bash
kubectl -n openbi describe externalsecret openbi-db-credentials
Common issues:

ClusterSecretStore misconfigured (check ESO logs)

IRSA role for ESO not attached to its ServiceAccount

Secret path in Secrets Manager doesn't match the ExternalSecret
