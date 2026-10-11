# Deployment Guide

End-to-end deployment of OpenBI on AWS.

## ⚠️ Not verified

This document describes a deployment procedure that has **not been
executed against a real AWS account**. The scripts, Terraform modules,
and Kubernetes manifests are correct as written, but the actual
end-to-end deployment is untested. See `verification.md` for the
complete status.

**What this means:** if you run these commands, you'll create real AWS
resources. They are correct as code. Whether they succeed on the first
attempt depends on factors this repo cannot verify without a live
account — IAM permissions of the caller, region-specific service
availability, quota limits, and so on.

## Prerequisites

Installed on the machine running the deploy:

| Tool | Version | Purpose |
| --- | --- | --- |
| AWS CLI | v2 | AWS API access |
| Terraform | ≥ 1.5 | Infrastructure provisioning |
| kubectl | ≥ 1.28 | Kubernetes access |
| Helm | ≥ 3.13 | Third-party controller installation |
| Docker | any recent | Building the FastAPI image |

Plus:

- **AWS credentials** configured via `aws configure`, environment
  variables, or an SSO profile. The caller must have permissions to
  create VPCs, EKS clusters, RDS instances, IAM roles, S3 buckets,
  SQS queues, CloudWatch log groups, and Secrets Manager secrets.
- **Docker running** if you intend to push the FastAPI image to ECR.
- **A shell** (bash or compatible).

## Quick start

```bash
# Clone the repo
git clone https://github.com/adnanphp/openbi-aws-cloud.git
cd openbi-aws-cloud

# Dry-run (recommended first)
./scripts/deploy.sh

# Actually deploy
./scripts/deploy.sh --apply
The script wraps the steps below. It uses terraform apply for the
infrastructure and helm/kubectl for the Kubernetes layer.

Manual deployment
If you prefer to run each step manually:

1. Terraform
bash
cd terraform/environments/dev
terraform init
terraform apply -var="bucket_suffix=$(aws sts get-caller-identity --query Account --output text)"
This creates:

VPC with public/private subnets across 2 AZs

EKS cluster + node groups (on-demand + spot)

IAM roles for EKS, EBS CSI, ALB Controller, ESO

ECR repository

S3 buckets (raw, processed, models)

RDS PostgreSQL instance

SQS queues (events + DLQ)

CloudWatch log groups, dashboard, alarms

Secrets Manager IRSA role

Time: ~15–20 minutes for the first apply. EKS and RDS take the
longest.

2. Kubeconfig
bash
aws eks update-kubeconfig --name openbi-dev --region eu-central-1
kubectl get nodes
Two nodes should appear (one on-demand, one spot).

3. Install controllers
External Secrets Operator:

bash
cd terraform/environments/dev
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ESO_ROLE_ARN
AWS Load Balancer Controller:

bash
ALB_ROLE_ARN=$(terraform output -raw alb_controller_role_arn)
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "use-vpc-id-from-console")

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=openbi-dev \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN \
  --set region=eu-central-1 \
  --set vpcId=$VPC_ID
4. Apply Kubernetes resources
bash
# Namespaces
kubectl apply -f kubernetes/namespaces/

# Cluster add-ons (Fluent Bit, CloudWatch agent)
kubectl apply -f kubernetes/cluster-addons/

# ClusterSecretStore
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml

# OpenBI application (after substituting placeholders — see below)
kubectl apply -k kubernetes/openbi-app/overlays/dev
5. Substitute placeholders
The Kubernetes manifests contain REPLACE-WITH-* and REPLACE tokens
that must be replaced with values from Terraform outputs before
applying:

Placeholder	Where	Value from
REPLACE-WITH-ECR-URL	kubernetes/openbi-app/base/fastapi-deployment.yaml	terraform output -raw ecr_repository_url
openbi-raw-REPLACE	kubernetes/openbi-app/base/configmap.yaml	terraform output -raw s3_raw_bucket
openbi-processed-REPLACE	kubernetes/openbi-app/base/configmap.yaml	terraform output -raw s3_processed_bucket
openbi-models-REPLACE	kubernetes/openbi-app/base/configmap.yaml	terraform output -raw s3_models_bucket
openbi-events-REPLACE	kubernetes/openbi-app/base/configmap.yaml	terraform output -raw sqs_main_queue_url
A future enhancement will automate this substitution in deploy.sh.

6. Create initial secrets
Some secrets must exist in Secrets Manager before External Secrets can
sync them:

bash
# Superset secret key (random)
aws secretsmanager create-secret \
  --name openbi/dev/superset \
  --secret-string "{\"secret_key\": \"$(openssl rand -hex 32)\"}"
RDS creates the openbi/dev/db secret automatically (with
manage_master_user_password = true). The secret name follows the RDS
convention — check with:

bash
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `rds`)].Name'
If the name doesn't match openbi/dev/db, either update the
ExternalSecret or create an alias secret.

7. Verify
bash
# Pods running
kubectl -n openbi get pods

# ExternalSecret synced
kubectl -n openbi get externalsecret

# Ingress created (ALB may take 2-3 minutes)
kubectl -n openbi get ingress
Post-deployment
Building and pushing the FastAPI image
Before the FastAPI pods can start, the image must exist in ECR:

bash
cd terraform/environments/dev
ECR_URL=$(terraform output -raw ecr_repository_url)

cd ../../..
./scripts/build-and-push.sh $ECR_URL v0.1.0
This builds the FastAPI image from the OpenBI source repo and pushes
it. The OPENBI_SRC environment variable controls where the source
repo lives (default: ~/projects/openbi).

Accessing the FastAPI API
The ALB is internal by default. To reach it from your laptop:

Option A: Session Manager port forwarding

bash
# Get a node's instance ID
NODE_ID=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' | sed 's/.*-//')

# Start SSM session (requires the SSM agent on nodes)
aws ssm start-session --target $NODE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["api.openbi.internal"],"portNumber":["80"],"localPortNumber":["8080"]}'
Option B: bastion host (not included in this repo)

Option C: temporarily make the Ingress internet-facing

bash
# Edit kubernetes/openbi-app/base/ingress.yaml
# Change alb.ingress.kubernetes.io/scheme: internal → internet-facing
kubectl apply -k kubernetes/openbi-app/overlays/dev
The ALB is recreated with a public DNS name. Use with caution.

Troubleshooting
See troubleshooting.md.

Tearing down
See teardown.md.

What can go wrong
Even a correct configuration can fail on a real AWS account. Common
issues:

Symptom	Likely cause
terraform apply fails on VPC creation	Caller lacks ec2:*Vpc* permissions
EKS cluster creation times out	Region unavailable, or IAM role misconfigured
RDS creation fails	Instance class unavailable in region
Pods stuck in ImagePullBackOff	Image not pushed to ECR, or node role lacks ECR read
ExternalSecret shows SecretSyncedError	Secret doesn't exist in Secrets Manager, or IRSA role misconfigured
ALB never appears	ALB Controller not installed, or Ingress has wrong ingressClassName
Each is documented in troubleshooting.md.

Verification status
Not verified against real AWS. See verification.md.
