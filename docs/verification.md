# Verification status

This document is deliberately explicit about what has been verified and
what has not. Cloud infrastructure that has not been applied to a real
provider has real limitations, and this repository is honest about them.

## Verification tiers

| Tier | Meaning |
|---|---|
| ✅ **Syntax** | Valid syntax for the language (HCL, YAML, JSON) |
| ✅ **Static** | Passes `terraform validate`, `tflint`, `kubeconform` |
| ⚠️ **Plan** | `terraform plan` runs but does not create resources |
| ❌ **Applied** | Deployed to a real AWS account and functioning |
| ❌ **Operational** | Running under load, monitored, costs measured |

## Current status

| Layer | Syntax | Static | Plan | Applied |
|---|---|---|---|---|
| Terraform — VPC module | ✅ | ✅ | ⚠️ | ❌ |
| Terraform — dev environment | ✅ | ✅ | ⚠️ | ❌ |
| Kubernetes manifests | ✅ | ⏳ (not yet) | — | ❌ |
| IAM policies | ✅ | ⏳ (not yet) | — | ❌ |
| Scripts | ✅ | — | — | ❌ |

Legend:
- ✅ verified
- ⚠️ partially — see notes below
- ⏳ not yet applicable (component not built)
- ❌ not verified
- — not applicable

## Notes

### Terraform — Plan status

`terraform plan` was not run because it requires AWS credentials to
query the provider for AMI IDs, availability zones, and other
account-specific data. The correct command to try is:

```bash
cd terraform/environments/dev
terraform init
terraform plan
This requires:

AWS credentials with read permissions (aws sts get-caller-identity
must work)

A configured region

terraform plan will not create any resources. It will produce an
estimated action list. This is safe to run with any AWS account,
including one with no billing set up — the plan does not incur costs.

Terraform — Applied status
Not verified. No AWS account has been used. The following are
therefore unverified:

Whether the IAM permissions required for terraform apply are
correctly assumed by the caller

Whether the chosen region has all required instance types

Whether the security group rules and route tables actually work
together for real traffic

Whether VPC Flow Logs actually appear in CloudWatch (they should,
but this has not been observed)

Whether quotas (VPC count, NAT Gateway count, EIP count) allow the
configuration

What can be verified locally
Everything in the Syntax and Static columns:

bash
./scripts/validate.sh
This runs terraform fmt -check, terraform init -backend=false,
terraform validate, and (if installed) tflint. It requires no AWS
credentials and creates no resources.

Cost of verification
If you choose to verify the VPC module against a real AWS account:

VPC, subnets, route tables, security groups, IGW: free

1 NAT Gateway: ~$32/month (this is the only meaningful cost)

VPC Flow Logs to CloudWatch: a few cents per GB ingested

The full VPC can be created and destroyed in under 10 minutes. The
cost of verification is therefore very close to $0 if the resources are
torn down immediately after the verification, since NAT Gateway
billing is hourly.

See teardown.md (to be written) for the exact cleanup sequence.

Integrity
Every claim in this repository should be traceable to one of these
tiers. If a claim cannot be verified to the level it implies, either
the claim or the verification tier should be adjusted. This section is
the anchor for that discipline.

---

## Current status (all phases A1–A11 complete)

| Layer | Syntax | Static | Applied |
| --- | --- | --- | --- |
| Terraform — all modules | ✅ | ✅ | ❌ |
| Terraform — dev composition | ✅ | ✅ | ❌ |
| Kubernetes manifests | ✅ | ⏳ | ❌ |
| IAM trust policies | ✅ | ✅ | ❌ |
| Shell scripts | ✅ | — | ❌ |
| End-to-end deployment | — | — | ❌ |

**Legend:**
- ✅ verified
- ⏳ not yet validated (kubeconform not wired into CI)
- ❌ not verified
- — not applicable

## What's not validated

- **Kubernetes manifests** are syntactically correct YAML but not
  validated by `kubeconform` in CI. Adding that is a documented future
  enhancement.
- **Shell scripts** have not been executed end-to-end.
- **`terraform plan`** has not been run (would require AWS credentials
  to query provider data sources).
- **The complete deployment procedure** has not been executed.

## What would change this

Running `terraform plan` against a real AWS account (read-only, no
resources created) would move the Terraform rows from ⚠️ to ✅. Running
`terraform apply` would move them to "Applied."

Both are documented in `deployment.md`. Neither is required to use this
repo as a reference.
