# EKS — The Kubernetes Cluster

The EKS module (`terraform/modules/eks/`) provisions the AWS-managed
Kubernetes control plane and two managed node groups. This document
explains every design decision.

## Architecture
Kubernetes API (private endpoint)
│
│
┌─────────────────────┼─────────────────────┐
│ │ │
▼ ▼ ▼
Private subnet A Private subnet B (more subnets)
│ │
│ ┌──────────────────┴──────────────────┐
│ │ │
▼ ▼ ▼
On-demand node Spot nodes (0–3)
(critical workloads) (user workloads)
│ │
└──────────┬──────────────────────────┘
│
▼
┌──────────────────────┐
│ Control plane logs │
│ → CloudWatch │
│ │
│ OIDC provider │
│ → IRSA │
└──────────────────────┘

text

## Design decisions

### Managed node groups, not self-managed

AWS manages the node lifecycle: AMI updates, patching, replacement on
failure. The alternative — self-managed Auto Scaling Groups that you
configure and patch yourself — is more work for no benefit in this
project.

### Two node groups: on-demand + spot

**On-demand group:** `t3.medium`, 1–2 nodes. Runs critical system
workloads (CoreDNS, kube-proxy, cluster-autoscaler). Cannot be
interrupted.

**Spot group:** `t3.medium` / `t3a.medium` / `t2.medium` (mixed),
0–3 nodes. Runs user workloads. ~70% cheaper than on-demand, but AWS
can reclaim the instance with 2 minutes notice.

The spot group is the target of the Cluster Autoscaler. When OpenBI
pods are pending, more spot nodes appear. When they're idle, they
disappear.

### Private API endpoint

The Kubernetes API server is reachable only from within the VPC. To
reach it from your laptop, you need one of:

- A bastion host in a public subnet
- AWS Systems Manager Session Manager
- A VPN connection
- Temporarily flipping `endpoint_public_access` to `true` with a
  CIDR allowlist

For a lab that won't actually be deployed, private-only is the more
secure default and demonstrates the correct production pattern.

### Control plane logging to CloudWatch

EKS emits five log types:

| Type | What it captures |
| --- | --- |
| `api` | API server logs |
| `audit` | Who did what, when, from where |
| `authenticator` | Authentication attempts |
| `controllerManager` | The kube-controller-manager |
| `scheduler` | The scheduler |

All five are enabled, sent to a CloudWatch log group
(`/aws/eks/openbi-dev/cluster`), with 7-day retention. In production,
you'd extend retention and possibly route to a SIEM. For a lab, 7 days
is enough to debug.

### OIDC provider for IRSA

The OIDC provider is created here (in A4) because it requires the
cluster to exist. It's what makes IRSA work:
Pod (using a ServiceAccount)
│
│ requests a token
▼
Kubernetes API server
│
│ issues a JWT signed by the cluster's OIDC issuer
▼
Pod presents JWT to AWS STS
│
│ STS validates the JWT against the OIDC provider
▼
STS returns short-lived credentials for the mapped IAM role
│
▼
Pod uses credentials (typically valid 15 min to 12 h)

text

No long-lived credentials. No rotation to manage. Every pod that needs
AWS access gets its own IAM role scoped to its specific permissions.

### Cluster add-ons

Four add-ons are installed via the EKS API (not Helm):

| Add-on | Purpose |
| --- | --- |
| `vpc-cni` | Assigns VPC-native IPs to pods |
| `coredns` | In-cluster DNS |
| `kube-proxy` | Network rules for Services |
| `aws-ebs-csi-driver` | Provisions EBS volumes for PVCs |

The EBS CSI driver needs its own IRSA role (created in this module) so
it can call the EBS APIs on behalf of PersistentVolumeClaims.

## What's not in A4

- **Cluster Autoscaler** — a Kubernetes Deployment, not part of cluster
  provisioning. Manifests live in `kubernetes/cluster-autoscaler/`.
- **AWS Load Balancer Controller** — a Kubernetes Deployment, installed
  via Helm in A8. README lives in `kubernetes/aws-load-balancer-controller/`.
- **External Secrets Operator** — a Kubernetes Deployment, installed via
  Helm in A9. README lives in `kubernetes/external-secrets/`.
- **OpenBI application manifests** — Phase A10. Placeholder in
  `kubernetes/openbi-app/`.

## Verification status

**Not verified against real AWS.** The Terraform module is statically
validated, and the JSON manifests are syntactically valid YAML. None of
it has been applied. See `verification.md`.

Applying this module against a real account would create:

- 1 EKS cluster control plane (~$73/month)
- 1–2 on-demand nodes (~$30/month each)
- 0–3 spot nodes (variable, ~$10/month each)
- CloudWatch log storage (negligible)

**Total for a running cluster:** ~$100–130/month, dominated by the
control plane and one on-demand node.

## Cost optimization notes

If someone were to actually run this:

1. **Tear down when not in use.** A `terraform destroy` at the end of
   the day eliminates almost all cost.
2. **Use Fargate profiles** instead of EC2 nodes for even lower idle
   cost (pods only cost money while running).
3. **Reduce control plane cost** — there's no way to do this. EKS
   control plane is a fixed ~$73/month.
4. **Spot for everything** — the on-demand node is required by some
   AWS-managed pods but the spot group handles the actual workloads.

## What maps to GCP

| AWS | GCP |
| --- | --- |
| EKS | GKE |
| Managed node groups | Node pools |
| On-demand + spot | On-demand + preemptible/spot |
| Private endpoint | Private cluster |
| Control plane logs | Cloud Logging |
| OIDC provider | Workload Identity Federation |
| IRSA | Workload Identity |
| Cluster add-ons | GKE add-ons |

The concept is identical: managed Kubernetes control plane, worker node
groups in private subnets, workload identity for pods, managed logging.

The commands and the manifests change. The architecture does not.

## What A4 delivers

| Artifact | Purpose |
| --- | --- |
| `terraform/modules/eks/` | EKS cluster, node groups, OIDC, add-ons |
| `kubernetes/namespaces/` | The three namespaces OpenBI uses |
| `kubernetes/cluster-autoscaler/` | Manifests + IRSA setup doc |
| `kubernetes/aws-load-balancer-controller/` | README describing the future install |
| `kubernetes/external-secrets/` | README describing the future install |
| `kubernetes/openbi-app/` | Placeholder for A10 |
| `docs/eks.md` | This document |
