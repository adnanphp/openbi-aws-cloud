# Troubleshooting

Common failure modes when deploying OpenBI on AWS, and how to fix them.

## Terraform

### "Error: creating EKS Cluster: InvalidParameterException: Role ARN is not valid"

The EKS cluster role wasn't created before the cluster. Check:

```bash
cd terraform/environments/dev
terraform state list | grep iam_role
If the IAM role is missing from state, something went wrong during the
iam module apply. Re-run:

bash
terraform apply -target=module.iam
terraform apply
"Error: creating RDS DB Instance: DBSubnetGroupNotFoundFault"
The subnet group wasn't created. This usually means the VPC module
didn't create subnets successfully. Check:

bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"
"Error: creating S3 Bucket: BucketAlreadyExists"
The bucket name collides with another AWS account's bucket. This is why
bucket_suffix exists — set it to your account ID:

bash
terraform apply -var="bucket_suffix=$(aws sts get-caller-identity --query Account --output text)"
EKS
"error: You must be logged in to the server (Unauthorized)"
The kubeconfig is stale or points at the wrong cluster. Refresh:

bash
aws eks update-kubeconfig --name openbi-dev --region eu-central-1
Nodes not Ready after 10 minutes
Check node group status:

bash
aws eks describe-nodegroup --cluster-name openbi-dev --nodegroup-name openbi-dev-on-demand
If nodes are healthy in EC2 but not Ready in Kubernetes, the issue is
usually:

VPC CNI not installed correctly

Node role missing permissions (unable to register with cluster)

Subnets don't have the kubernetes.io/role/internal-elb tag

Pods
Pods stuck in ImagePullBackOff
The image isn't in ECR, or the node can't pull it.

bash
# Check if the image exists
aws ecr list-images --repository-name openbi

# Check the node role has ECR read
aws iam list-attached-role-policies --role-name openbi-dev-eks-node-role
The node role should have AmazonEC2ContainerRegistryReadOnly.

Pods stuck in Pending
The cluster has no capacity, or the Cluster Autoscaler isn't scaling.

bash
kubectl describe pod -n openbi <pod-name>
Look for "0/2 nodes are available." Then check:

bash
# Cluster Autoscaler running?
kubectl -n kube-system get pods | grep cluster-autoscaler

# If not, check the IRSA role for the autoscaler
kubectl -n kube-system describe sa cluster-autoscaler
Pods crash-looping on start
Usually a missing secret or config. Check pod logs:

bash
kubectl -n openbi logs <pod-name>
If it says "connection refused" to a database, the ExternalSecret may
not have synced yet.

External Secrets
ExternalSecret shows SecretSyncedError
bash
kubectl -n openbi describe externalsecret <name>
Common causes:

Secret doesn't exist in Secrets Manager. Verify:

bash
aws secretsmanager get-secret-value --secret-id openbi/dev/db
IRSA role not attached to ESO's ServiceAccount. Verify:

bash
kubectl -n external-secrets get sa external-secrets -o yaml | grep role-arn
ClusterSecretStore misconfigured. Verify:

bash
kubectl get clustersecretstore aws-secrets-manager -o yaml
kubectl -n external-secrets logs -l app.kubernetes.io/name=external-secrets
RDS secret has a different name
RDS auto-generates the secret name based on the instance identifier.
It doesn't match openbi/dev/db by default. Two fixes:

Option A: Update the ExternalSecret to reference the actual RDS
secret name.

Option B: Create an alias secret at openbi/dev/db with the same
value.

Ingress / ALB
ALB never appears
bash
# Is the ALB Controller running?
kubectl -n kube-system get deployment aws-load-balancer-controller

# Does the Ingress have the right ingressClassName?
kubectl -n openbi get ingress <name> -o jsonpath='{.spec.ingressClassName}'
Should be alb. If not, the Ingress is being handled by another
controller (or none).

ALB appears but 502/503 errors
The target group has no healthy targets. Check:

bash
# Are pods ready?
kubectl -n openbi get pods

# Does the healthcheck path respond?
kubectl -n openbi port-forward svc/fastapi 8000:8000
curl http://localhost:8000/health
If the healthcheck path returns non-2xx, the target group marks targets
unhealthy.

ALB not reachable from laptop
The ALB is internal by default. See deployment.md for access
options (SSM, bastion, or temporarily flipping to internet-facing).

Cluster Autoscaler
Cluster Autoscaler not scaling
bash
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=100
Common messages:

"No candidates for scale up" — the node group tags are missing

"failed to get node group" — IRSA role misconfigured

"Not enough nodes" — the node group max size is reached

The spot node group needs these tags for autoscaler discovery:

text
k8s.io/cluster-autoscaler/enabled=true
k8s.io/cluster-autoscaler/<cluster-name>=owned
These are set by the EKS module. Verify:

bash
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].Tags'
General debugging
"Which IAM role is this pod using?"
bash
kubectl -n openbi exec <pod> -- env | grep AWS
If AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE are set, the pod
has an IRSA role.

"What did Terraform create?"
bash
cd terraform/environments/dev
terraform state list
terraform output
"What's happening in the cluster?"
bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30
Verification status
Not verified against real AWS. The failure modes above are
documented based on typical AWS behavior, not observed in a live
deployment. See verification.md.
