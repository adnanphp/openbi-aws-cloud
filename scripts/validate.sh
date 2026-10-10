#!/usr/bin/env bash
# Static validation for the Terraform and Kubernetes configuration.
#
# Runs entirely offline — no AWS credentials or account required.
#
# Prerequisites:
#   - terraform (>= 1.5.0)
#   - tflint (optional but recommended)

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> terraform fmt check"
if ! terraform fmt -check -recursive terraform/ 2>/dev/null; then
  echo "    Some files need formatting. Run: terraform fmt -recursive terraform/"
  exit 1
fi
echo "    OK"

echo
echo "==> terraform init (backend=false) in environments/dev"
(cd terraform/environments/dev && terraform init -backend=false -input=false >/dev/null)
echo "    OK"

echo
echo "==> terraform validate in environments/dev"
(cd terraform/environments/dev && terraform validate)
echo "    OK"

if command -v tflint >/dev/null 2>&1; then
  echo
  echo "==> tflint"
  (cd terraform/environments/dev && tflint --init >/dev/null 2>&1 || true)
  (cd terraform/environments/dev && tflint)
  echo "    OK"
else
  echo
  echo "==> tflint not installed, skipping (install: https://github.com/terraform-linters/tflint)"
fi

echo
echo "==> All validations passed"
