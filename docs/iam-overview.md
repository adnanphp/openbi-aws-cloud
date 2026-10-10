# IAM Overview

The IAM model for the OpenBI AWS deployment. Every role, why it
exists, and how it relates to the rest of the architecture.

## Principles

1. **No IAM users.** Everything is roles assumed by AWS services or
   federated identities.
2. **No long-lived access keys.** Nothing in the repository, nothing in
   the cluster.
3. **IRSA for pod-level AWS access.** Pods never hold credentials.
4. **AWS-managed policies where possible.**
5. **Trust policies scoped to a specific principal.** No `Principal: "*"`.

## The roles (Phase A2)

### `openbi-dev-eks-cluster-role`

**Assumed by:** EKS control plane (`eks.amazonaws.com`)
**Purpose:** lets EKS manage AWS resources on your behalf (ENIs, load
balancers for the API server)
**Attached policies:**
- `AmazonEKSClusterPolicy` (AWS-managed)
- `AmazonEKSVPCResourceController` (AWS-managed)

### `openbi-dev-eks-node-role`

**Assumed by:** EC2 instances (`ec2.amazonaws.com`)
**Purpose:** lets worker nodes register with the cluster, assign pod
IPs, and pull images from ECR
**Attached policies:**
- `AmazonEKSWorkerNodePolicy` (AWS-managed)
- `AmazonEKS_CNI_Policy` (AWS-managed)
- `AmazonEC2ContainerRegistryReadOnly` (AWS-managed)

### `openbi-dev-irsa-template-role`

**Assumed by:** (in later phases) a Kubernetes ServiceAccount via
federated OIDC
**Purpose:** template for pod-level IAM roles
**Attached policies:** none
**Status:** exists as a documented pattern. Cannot be successfully
assumed until the EKS cluster's OIDC provider is registered in IAM
(Phase A4) and a ServiceAccount is annotated with this role's ARN.

## Why no long-lived credentials

The correct pattern for any AWS workload is:

1. **For AWS services (EKS, EC2):** use a service role. AWS's own
   services assume these roles; no keys exist anywhere.
2. **For Kubernetes pods:** use IRSA. A pod is annotated with a
   Kubernetes ServiceAccount; that ServiceAccount is annotated with an
   IAM role ARN; the pod receives a short-lived token that it exchanges
   for STS credentials. The credentials expire (default 15 minutes to
   12 hours) and can never be leaked because they never touch a file.
3. **For developers and CI:** use federated identity (SSO, OIDC with
   GitHub Actions). No keys.

Long-lived access keys are the most common cause of AWS security
incidents. This repository does not use them, anywhere.

## What's not in A2

Roles for later phases:

| Role | Phase | Why it's later |
| --- | --- | --- |
| EBS CSI driver role | A4 | Part of EKS add-ons |
| Cluster autoscaler role | A4 | Part of EKS workloads |
| RDS enhanced monitoring | A6 | RDS-specific |
| Application roles (IRSA per service) | A4–A8 | Depends on which services exist |
| ALB Ingress Controller | A8 | Needs the ALB to exist |

Each of these is created in its own phase so that role and workload
stay together in one commit.

## How to review this configuration

```bash
# Validate the Terraform
cd terraform/environments/dev
terraform init -backend=false
terraform validate

# Validate the JSON policies
for f in ../../../iam/policies/*.json; do
  jq empty "$f" && echo "OK: $f"
done
Both commands run offline. Neither creates any AWS resources.

Verification status
See verification.md. The IAM configuration is statically valid and
matches AWS's published trust-policy schemas, but has not been assumed
against a real AWS account.
