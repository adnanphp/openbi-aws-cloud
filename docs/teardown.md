# Teardown Guide

How to safely destroy an OpenBI deployment.

## ⚠️ Read first

Teardown destroys real AWS resources. Before running it:

1. **Check what will be destroyed.** Run the teardown script *without*
   `--yes` first. It prints the exact commands it would run.
2. **Confirm there's nothing important in the S3 buckets.** The buckets
   are deleted by `terraform destroy`.
3. **Note that RDS backups are deleted.** The instance is deleted with
   `skip_final_snapshot = true`, so no final snapshot is taken.
4. **Understand that deleted resources cannot be recovered.** Unlike
   EC2 instances in "stopped" state, a destroyed EKS cluster or RDS
   instance is gone.

## The safe teardown

```bash
./scripts/teardown.sh
This prints what would happen. Review it.

bash
./scripts/teardown.sh --yes
This actually destroys.

What gets destroyed, in order
OpenBI Ingresses — deleting these makes the ALB Controller
delete the ALBs. This must happen first.

External Secrets ClusterSecretStore — deleted before ESO so
ESO doesn't error trying to reach a deleted store.

Cluster add-ons (Fluent Bit, CloudWatch agent) — DaemonSets
removed from all nodes.

Helm releases — External Secrets Operator and ALB Controller.

Kubernetes namespaces — openbi, external-secrets,
amazon-cloudwatch. Deleting the namespace deletes everything in it.

Terraform destroy — VPC, EKS, RDS, S3, SQS, CloudWatch, Secrets,
IAM. In reverse dependency order.

Why the order matters
Ingresses before Helm: if you uninstall the ALB Controller before
deleting the Ingresses, the ALBs become orphaned. Nothing knows to
delete them. Deleting Ingresses first lets the controller clean up.

ClusterSecretStore before ESO: if you uninstall ESO first, the
ClusterSecretStore remains but has no controller. Harmless but messy.
Deleting it first is cleaner.

Kubernetes before Terraform: Terraform destroys the EKS cluster,
which takes everything in it down. That works, but it's abrupt — pods
are killed mid-operation. Doing the Kubernetes cleanup first is
graceful.

Manual teardown
If you need to run each step:

bash
# 1. Delete Ingresses (removes ALBs)
kubectl delete -k kubernetes/openbi-app/overlays/dev

# 2. Delete ClusterSecretStore
kubectl delete -f kubernetes/external-secrets/cluster-secret-store.yaml

# 3. Delete cluster add-ons
kubectl delete -f kubernetes/cluster-addons/

# 4. Uninstall Helm releases
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall external-secrets -n external-secrets

# 5. Delete namespaces
kubectl delete namespace openbi
kubectl delete namespace external-secrets
kubectl delete namespace amazon-cloudwatch

# 6. Terraform destroy
cd terraform/environments/dev
terraform destroy -var="bucket_suffix=$(aws sts get-caller-identity --query Account --output text)"
Verifying cleanup
After teardown, check for orphaned resources:

bash
# EKS clusters
aws eks list-clusters

# RDS instances
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'

# S3 buckets
aws s3 ls | grep openbi

# SQS queues
aws sqs list-queues

# Load balancers
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'

# Secrets
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `openbi`)].Name'

# CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /aws/openbi
The most likely orphan: an ALB that wasn't deleted because an
Ingress was deleted after the controller was uninstalled. Check
aws elbv2 describe-load-balancers and manually delete with:

bash
aws elbv2 delete-load-balancer --load-balancer-arn <ARN>
Cost note
This repo does not discuss costs. If you are concerned about billing,
check the AWS Billing console after teardown to confirm no resources
remain. The verification above covers every resource type this repo
creates.

Verification status
Not verified against real AWS. See verification.md.
