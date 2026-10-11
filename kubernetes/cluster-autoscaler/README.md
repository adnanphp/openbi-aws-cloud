# Cluster Autoscaler

The Cluster Autoscaler watches for pods that can't be scheduled due to
insufficient node capacity, and scales the spot node group accordingly.
When nodes are idle, it scales the group back down.

## IRSA setup

The autoscaler runs as a Kubernetes Deployment and needs an IAM role to
call the Auto Scaling APIs. It uses IRSA (no long-lived credentials).

**Required before applying the Deployment:**

```bash
# Set variables
CLUSTER_NAME=openbi-dev
AWS_REGION=eu-central-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

# Create the trust policy
cat > /tmp/autoscaler-trust.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

# Create the role
aws iam create-role \
  --role-name openbi-dev-cluster-autoscaler \
  --assume-role-policy-document file:///tmp/autoscaler-trust.json

# Attach the required policy
aws iam attach-role-policy \
  --role-name openbi-dev-cluster-autoscaler \
  --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess

# Annotate the ServiceAccount (done in the deployment YAML below via
# `eks.amazonaws.com/role-arn` — replace the placeholder with this ARN)
Deployment
See deployment.yaml in this directory. It contains:

A ServiceAccount annotated with the IAM role ARN

RBAC (ClusterRole, ClusterRoleBinding)

The Deployment

Before applying, replace the placeholder eks.amazonaws.com/role-arn
in deployment.yaml with the ARN created above.
