"""ECR operations via boto3.

Examples of the AWS SDK calls used to inspect an ECR repository. This
mirrors the CLI commands in scripts/build-and-push.sh but as Python.

To use against real AWS:

    export AWS_REGION=eu-central-1
    export AWS_PROFILE=your-profile    # or AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
    python python/ecr_operations.py

The script auto-detects the repository by name. It does not create or
modify anything — read-only operations only.
"""

from __future__ import annotations

import os
import sys

import boto3
from botocore.exceptions import ClientError


def get_ecr_client():
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "eu-central-1"
    return boto3.client("ecr", region_name=region)


def list_repositories(ecr, prefix: str = "openbi") -> list[dict]:
    """List ECR repositories whose name starts with `prefix`."""
    response = ecr.describe_repositories()
    repos = response.get("repositories", [])
    return [r for r in repos if r["repositoryName"].startswith(prefix)]


def list_images(ecr, repo_name: str) -> list[dict]:
    """List all images in a repository."""
    images: list[dict] = []
    paginator = ecr.get_paginator("describe_images")
    for page in paginator.paginate(repositoryName=repo_name):
        images.extend(page.get("imageDetails", []))
    return images


def describe_repository(ecr, repo_name: str) -> dict | None:
    """Return repository metadata, or None if it doesn't exist."""
    try:
        response = ecr.describe_repositories(repositoryNames=[repo_name])
        repos = response.get("repositories", [])
        return repos[0] if repos else None
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "RepositoryNotFoundException":
            return None
        raise


def main() -> int:
    ecr = get_ecr_client()

    print("==> Repositories with prefix 'openbi'")
    repos = list_repositories(ecr)
    if not repos:
        print("    (none found)")
        return 0

    for repo in repos:
        print(f"    - {repo['repositoryName']}")
        print(f"      URI: {repo['repositoryUri']}")
        print(f"      Created: {repo['createdAt']}")
        print(f"      Tag mutability: {repo['imageTagMutability']}")
        print(f"      Scan on push: {repo.get('imageScanningConfiguration', {}).get('scanOnPush')}")

    # Show images for the first matching repo
    target = repos[0]["repositoryName"]
    print(f"\n==> Images in {target}")
    images = list_images(ecr, target)
    if not images:
        print("    (no images)")
    else:
        for img in images[:20]:  # cap at 20
            tags = ", ".join(img.get("imageTags", [])) or "(untagged)"
            pushed = img.get("imagePushedAt")
            size_mb = img.get("imageSizeInBytes", 0) / (1024 * 1024)
            print(f"    - {tags}")
            print(f"      pushed: {pushed}  size: {size_mb:.1f} MB")

    return 0


if __name__ == "__main__":
    sys.exit(main())
