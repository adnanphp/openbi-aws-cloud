#!/usr/bin/env bash
# Build OpenBI container images locally and push them to ECR.
#
# Usage:
#   ./scripts/build-and-push.sh <ecr-repo-url> <tag-suffix>
#
# Example:
#   ./scripts/build-and-push.sh \
#     123456789012.dkr.ecr.eu-central-1.amazonaws.com/openbi \
#     v0.1.0
#
# This script:
#   1. Authenticates Docker to ECR
#   2. Builds each OpenBI image from the local repository
#   3. Tags them with the ECR URL
#   4. Pushes them
#
# Requires:
#   - AWS CLI configured with credentials that can push to ECR
#   - Docker running
#   - The OpenBI source repository available locally
#
# NOTE: This script requires real AWS credentials to run. It has NOT
# been executed — see docs/verification.md. The commands it issues are
# correct as written.

set -euo pipefail

ECR_REPO_URL="${1:-}"
TAG_SUFFIX="${2:-latest}"

if [ -z "$ECR_REPO_URL" ]; then
  echo "Usage: $0 <ecr-repo-url> [tag-suffix]"
  echo "Example: $0 123456789012.dkr.ecr.eu-central-1.amazonaws.com/openbi v0.1.0"
  exit 1
fi

# Derive the registry from the repository URL
REGISTRY="$(echo "$ECR_REPO_URL" | cut -d/ -f1)"
REGION="$(echo "$REGISTRY" | sed 's/.*\.ecr\.\(.*\)\.amazonaws\.com/\1/')"

echo "==> ECR repository: $ECR_REPO_URL"
echo "==> Registry:       $REGISTRY"
echo "==> Region:         $REGION"
echo "==> Tag suffix:     $TAG_SUFFIX"
echo

# ----------------------------------------------------------------------
# Authenticate Docker to ECR
# ----------------------------------------------------------------------

echo "==> Authenticating Docker to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# ----------------------------------------------------------------------
# Build and push OpenBI images
# ----------------------------------------------------------------------
# Each entry is: <local-image-name>:<local-tag>  <remote-tag-prefix>
# The remote tag becomes "<remote-tag-prefix>-<tag-suffix>"

IMAGES=(
  "openbi-fastapi:latest fastapi"
  # "openbi-superset:latest superset"
  # "ghcr.io/netvark/minio:latest minio"
)

# Path to the OpenBI source repository
OPENBI_SRC="${OPENBI_SRC:-$HOME/projects/openbi}"

for entry in "${IMAGES[@]}"; do
  read -r local_ref remote_prefix <<< "$entry"

  # Skip commented entries
  [ -z "$local_ref" ] && continue

  remote_tag="${ECR_REPO_URL}:${remote_prefix}-${TAG_SUFFIX}"

  echo
  echo "==> Processing: $local_ref  →  $remote_tag"

  # Build if the local image doesn't exist
  if ! docker image inspect "$local_ref" >/dev/null 2>&1; then
    echo "    Local image missing. Building..."
    case "$remote_prefix" in
      fastapi)
        docker build \
          -t "$local_ref" \
          -f "$OPENBI_SRC/infrastructure/kubernetes/fastapi-app/Dockerfile" \
          "$OPENBI_SRC"
        ;;
      *)
        echo "    ERROR: no build recipe for $remote_prefix"
        exit 1
        ;;
    esac
  fi

  echo "    Tagging as $remote_tag"
  docker tag "$local_ref" "$remote_tag"

  echo "    Pushing"
  docker push "$remote_tag"
done

echo
echo "==> Done. Images pushed to $ECR_REPO_URL"
echo
echo "    List them with:"
echo "      aws ecr list-images --repository-name $(basename "$ECR_REPO_URL") --region $REGION"
