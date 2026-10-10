# IAM

This directory contains IAM trust policies and documentation for the
OpenBI AWS deployment.

## Files

| File | Purpose |
| --- | --- |
| `policies/eks-cluster-trust.json` | Trust policy for the EKS control plane role |
| `policies/eks-node-trust.json` | Trust policy for the EC2 worker node role |
| `policies/irsa-trust.json` | Template showing the shape of an IRSA trust policy |
| `policies/README.md` | *(this file)* |

## Why trust policies are separate files

Trust policies are the JSON that answers: *"who is allowed to assume
this role?"* They are the security boundary of every IAM role.

They live as standalone files rather than inline HCL because:

1. **Readability.** A trust policy is a security document. It should be
   readable in isolation, not buried in a Terraform string.
2. **Reuse.** Other tools (AWS CLI, other IaC frameworks) can consume
   the same JSON.
3. **Documentation.** Reading the file tells you what the role is for
   without needing to understand Terraform.

The Terraform module references them with `file()`:

```hcl
assume_role_policy = file("${path.module}/../../../iam/policies/eks-cluster-trust.json")
The three trust policies
eks-cluster-trust.json
The EKS control plane assumes this role to manage AWS resources on your
behalf — ENIs for the API server endpoint, load balancers when the
cluster is public, and similar.

Service: eks.amazonaws.com
Attached AWS-managed policies: AmazonEKSClusterPolicy,
AmazonEKSVPCResourceController

eks-node-trust.json
EC2 instances running as Kubernetes worker nodes assume this role.

Service: ec2.amazonaws.com
Attached AWS-managed policies: AmazonEKSWorkerNodePolicy,
AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly

irsa-trust.json
This file contains placeholders and is not meant to be applied
directly. It shows the shape of an IRSA trust policy: a
Federated principal pointing at the cluster's OIDC provider, with
StringEquals conditions scoping it to a specific Kubernetes
ServiceAccount.

The actual IRSA roles are templated per service in future phases. This
file exists as a reference.

Design principles for this repository
No IAM users. Everything is roles assumed by services or
federated identities.

No long-lived access keys. Nothing in the repo, nothing in the
cluster.

IRSA for all pod-level AWS access. Pods never hold credentials.
The OIDC token is exchanged for short-lived STS credentials on
demand.

AWS-managed policies where possible. Custom policies only when
the AWS-managed option is too broad for the use case.

Trust policies scoped to a specific principal. No Principal: "*" anywhere in this repository.

What's not here (yet)
Application-specific IAM roles (each service module owns its own)

RDS enhanced monitoring role (Phase A6)

EBS CSI driver role (Phase A4)

ALB Ingress Controller role (Phase A8)

Custom least-privilege policies (later phases when there is a
concrete workload to scope them to)
