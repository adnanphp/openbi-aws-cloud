#!/usr/bin/env bash
# Tear down OpenBI from AWS.
#
# Reverse order of deploy.sh:
#
#   1. Delete Kubernetes manifests (Ingresses first so ALBs are removed)
#   2. Uninstall Helm releases
#   3. terraform destroy
#
# IMPORTANT: this destroys real AWS resources. Run without --yes first
# to see what would happen.
#
# Usage:
#   ./scripts/teardown.sh                # dry-run
#   ./scripts/teardown.sh --yes          # actually destroy
#   ./scripts/teardown.sh --env=dev      # override environment

set -euo pipefail

CONFIRM=false
ENV="dev"

for arg in "$@"; do
  case "$arg" in
    --yes) CONFIRM=true ;;
    --env=*) ENV="${arg#--env=}" ;;
    -h|--help)
      echo "Usage: $0 [--yes] [--env=dev]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
K8S_DIR="$REPO_ROOT/kubernetes"

run() {
  if [ "$CONFIRM" = true ]; then
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
# Warning
# ----------------------------------------------------------------------

step "Teardown — $ENV"

if [ "$CONFIRM" != true ]; then
  echo
  echo "  This is a DRY-RUN. Nothing will be destroyed."
  echo "  To actually destroy, run: $0 --yes"
  echo
fi

echo "  This will:"
echo "    1. Delete OpenBI Kubernetes resources (Ingresses first → ALB deleted)"
echo "    2. Uninstall External Secrets Operator and ALB Controller"
echo "    3. Delete Fluent Bit and CloudWatch agent DaemonSets"
echo "    4. Delete namespaces"
echo "    5. terraform destroy (VPC, EKS, RDS, S3, SQS, CloudWatch, Secrets, IAM)"

# ----------------------------------------------------------------------
# Step 1: Delete Kubernetes manifests (in reverse order of apply)
# ----------------------------------------------------------------------

step "1. Delete Kubernetes manifests"

# Delete Ingresses first — this triggers the ALB Controller to delete ALBs.
run kubectl delete -k "$K8S_DIR/openbi-app/overlays/$ENV" --ignore-not-found=true

# Delete ClusterSecretStore before uninstalling ESO.
run kubectl delete -f "$K8S_DIR/external-secrets/cluster-secret-store.yaml" --ignore-not-found=true

# Delete cluster add-ons.
run kubectl delete -f "$K8S_DIR/cluster-addons/" --ignore-not-found=true

# ----------------------------------------------------------------------
# Step 2: Uninstall Helm releases
# ----------------------------------------------------------------------

step "2. Uninstall Helm releases"

run helm uninstall aws-load-balancer-controller -n kube-system || true
run helm uninstall external-secrets -n external-secrets || true

# ----------------------------------------------------------------------
# Step 3: Delete namespaces
# ----------------------------------------------------------------------

step "3. Delete namespaces"

run kubectl delete namespace openbi --ignore-not-found=true
run kubectl delete namespace external-secrets --ignore-not-found=true
run kubectl delete namespace amazon-cloudwatch --ignore-not-found=true

# ----------------------------------------------------------------------
# Step 4: terraform destroy
# ----------------------------------------------------------------------

step "4. terraform destroy"

cd "$TF_DIR"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000000000")

run terraform destroy -input=false -auto-approve -var="bucket_suffix=$ACCOUNT_ID"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

step "Summary"

if [ "$CONFIRM" = true ]; then
  echo "  Teardown complete."
  echo
  echo "  Verify no orphaned resources:"
  echo "    aws eks list-clusters"
  echo "    aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'"
  echo "    aws s3 ls | grep openbi"
else
  echo "  This was a dry-run. Nothing was destroyed."
  echo
  echo "  To actually destroy:"
  echo "    ./scripts/teardown.sh --yes"
fi
