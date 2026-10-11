#!/usr/bin/env bash
# Show the current deployment status.
#
# Prints:
#   - AWS account and region
#   - Terraform outputs (if state exists)
#   - EKS cluster status
#   - Kubernetes resources in OpenBI namespaces
#   - Helm releases
#
# Read-only. Safe to run anytime.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/dev"

step() {
  echo
  echo "============================================================"
  echo " $*"
  echo "============================================================"
}

# ----------------------------------------------------------------------
# AWS identity
# ----------------------------------------------------------------------

step "AWS"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "  AWS credentials not configured."
  exit 0
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "eu-central-1")

echo "  Account: $ACCOUNT_ID"
echo "  Region:  $REGION"

# ----------------------------------------------------------------------
# Terraform
# ----------------------------------------------------------------------

step "Terraform"

if [ -f "$TF_DIR/terraform.tfstate" ]; then
  echo "  State file exists: $TF_DIR/terraform.tfstate"
  echo
  echo "  Resources:"
  (cd "$TF_DIR" && terraform state list 2>/dev/null | head -30) || echo "  (unable to read state)"
else
  echo "  No terraform state. Nothing deployed via Terraform."
fi

# ----------------------------------------------------------------------
# EKS
# ----------------------------------------------------------------------

step "EKS"

if aws eks describe-cluster --name "openbi-dev" --region "$REGION" >/dev/null 2>&1; then
  STATUS=$(aws eks describe-cluster --name "openbi-dev" --region "$REGION" --query 'cluster.status' --output text)
  VERSION=$(aws eks describe-cluster --name "openbi-dev" --region "$REGION" --query 'cluster.version' --output text)
  echo "  Cluster: openbi-dev"
  echo "  Status:  $STATUS"
  echo "  Version: $VERSION"
  echo
  echo "  Node groups:"
  aws eks list-nodegroups --cluster-name openbi-dev --region "$REGION" --query 'nodegroups[]' --output table
else
  echo "  Cluster 'openbi-dev' not found."
fi

# ----------------------------------------------------------------------
# Kubernetes
# ----------------------------------------------------------------------

step "Kubernetes"

if kubectl cluster-info >/dev/null 2>&1; then
  echo "  Nodes:"
  kubectl get nodes --no-headers 2>/dev/null | head -5 || echo "  (unable to list nodes)"

  for ns in openbi monitoring logging external-secrets amazon-cloudwatch; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      echo
      echo "  Pods in $ns:"
      kubectl -n "$ns" get pods --no-headers 2>/dev/null | head -10 || echo "  (none)"
    fi
  done

  echo
  echo "  Ingresses in openbi:"
  kubectl -n openbi get ingress --no-headers 2>/dev/null || echo "  (none)"
else
  echo "  kubectl cannot reach a cluster."
fi

# ----------------------------------------------------------------------
# Helm
# ----------------------------------------------------------------------

step "Helm releases"

for ns in kube-system external-secrets; do
  echo
  echo "  In $ns:"
  helm list -n "$ns" 2>/dev/null || echo "  (unable to list)"
done

echo
echo "Done."
