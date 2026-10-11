#!/usr/bin/env bash
# Deploy OpenBI to AWS.
#
# This script is a convenience wrapper around the sequence of steps
# documented in docs/deployment.md:
#
#   1. Verify AWS credentials
#   2. terraform apply (VPC, IAM, ECR, EKS, S3, RDS, SQS, ALB, CloudWatch, Secrets)
#   3. Update kubeconfig
#   4. Install cluster controllers via Helm (ALB Controller, ESO)
#   5. Apply Kubernetes manifests (namespaces, add-ons, app)
#
# IMPORTANT: this script is NOT verified against a real AWS account.
# It is a documented procedure, not an executed one. See
# docs/verification.md. Running it will create real AWS resources that
# incur charges.
#
# Usage:
#   ./scripts/deploy.sh              # dry-run: prints what would happen
#   ./scripts/deploy.sh --apply      # actually apply
#   ./scripts/deploy.sh --env=dev    # override environment (default: dev)

set -euo pipefail

# ----------------------------------------------------------------------
# Parse arguments
# ----------------------------------------------------------------------

APPLY=false
ENV="dev"

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --env=*) ENV="${arg#--env=}" ;;
    -h|--help)
      echo "Usage: $0 [--apply] [--env=dev]"
      echo
      echo "  --apply      Actually apply (default: dry-run)"
      echo "  --env=NAME   Environment (default: dev)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
K8S_DIR="$REPO_ROOT/kubernetes"

# ----------------------------------------------------------------------
# Helper
# ----------------------------------------------------------------------

run() {
  if [ "$APPLY" = true ]; then
    echo "  → $*"
    "$@"
  else
    echo "  (dry-run) $*"
  fi
}

step() {
  echo
  echo "============================================================"
  echo " $*"
  echo "============================================================"
}

# ----------------------------------------------------------------------
# Step 1: Verify AWS credentials
# ----------------------------------------------------------------------

step "1. Verify AWS credentials"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: terraform not found. Install: https://developer.hashicorp.com/terraform/install" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found." >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm not found. Install: https://helm.sh/docs/intro/install/" >&2
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not configured or invalid." >&2
  echo "Run: aws configure" >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "eu-central-1")
echo "  Account: $ACCOUNT_ID"
echo "  Region:  $REGION"
echo "  Env:     $ENV"

# ----------------------------------------------------------------------
# Step 2: terraform apply
# ----------------------------------------------------------------------

step "2. terraform apply"

cd "$TF_DIR"

echo "  Initializing Terraform..."
run terraform init -input=false

echo
echo "  Applying with bucket_suffix=$ACCOUNT_ID..."
run terraform apply -input=false -auto-approve -var="bucket_suffix=$ACCOUNT_ID"

if [ "$APPLY" = true ]; then
  echo
  echo "  Terraform outputs:"
  terraform output -json | head -40
fi

# ----------------------------------------------------------------------
# Step 3: Update kubeconfig
# ----------------------------------------------------------------------

step "3. Update kubeconfig"

CLUSTER_NAME=$(cd "$TF_DIR" && terraform output -raw eks_cluster_name 2>/dev/null || echo "openbi-$ENV")

echo "  Cluster: $CLUSTER_NAME"
run aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

if [ "$APPLY" = true ]; then
  echo
  echo "  Verifying cluster connectivity..."
  kubectl cluster-info || true
fi

# ----------------------------------------------------------------------
# Step 4: Install cluster controllers
# ----------------------------------------------------------------------

step "4. Install cluster controllers"

if [ "$APPLY" = true ]; then
  ESO_ROLE_ARN=$(cd "$TF_DIR" && terraform output -raw eso_role_arn)
  ALB_ROLE_ARN=$(cd "$TF_DIR" && terraform output -raw alb_controller_role_arn)
  VPC_ID=$(cd "$TF_DIR" && terraform output -raw vpc_id 2>/dev/null || terraform output -raw vpc_id 2>/dev/null || echo "")
fi

# External Secrets Operator
echo
echo "  Installing External Secrets Operator..."
run helm repo add external-secrets https://charts.external-secrets.io
run helm repo update
run helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn=${ESO_ROLE_ARN:-REPLACE}"

# AWS Load Balancer Controller
echo
echo "  Installing AWS Load Balancer Controller..."
run helm repo add eks https://aws.github.io/eks-charts
run helm repo update
run helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME:-REPLACE}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn=${ALB_ROLE_ARN:-REPLACE}" \
  --set region="${REGION:-eu-central-1}" \
  --set vpcId="${VPC_ID:-REPLACE}"

# ----------------------------------------------------------------------
# Step 5: Apply Kubernetes manifests
# ----------------------------------------------------------------------

step "5. Apply Kubernetes manifests"

echo
echo "  Namespaces..."
run kubectl apply -f "$K8S_DIR/namespaces/"

echo
echo "  Cluster add-ons (Fluent Bit, CloudWatch agent)..."
run kubectl apply -f "$K8S_DIR/cluster-addons/"

echo
echo "  ClusterSecretStore..."
run kubectl apply -f "$K8S_DIR/external-secrets/cluster-secret-store.yaml"

echo
echo "  OpenBI application..."
echo "  NOTE: the manifests contain REPLACE-WITH-* placeholders that"
echo "        must be substituted with Terraform outputs before applying."
echo "        A future enhancement will automate this substitution."
run kubectl apply -k "$K8S_DIR/openbi-app/overlays/$ENV"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

step "Summary"

if [ "$APPLY" = true ]; then
  echo "  Deployment complete."
  echo
  echo "  Next steps:"
  echo "    ./scripts/status.sh              # show what's deployed"
  echo "    ./scripts/teardown.sh            # tear down (dry-run)"
  echo "    ./scripts/teardown.sh --yes      # tear down (actually)"
else
  echo "  This was a dry-run. Nothing was applied."
  echo
  echo "  To apply:"
  echo "    ./scripts/deploy.sh --apply"
fi
