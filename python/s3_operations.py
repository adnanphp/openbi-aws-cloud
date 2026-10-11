"""S3 operations via boto3.

Examples of the AWS SDK calls that OpenBI uses for object storage.
Against real S3, these are the same operations the platform runs against
MinIO locally.

To use against real AWS:

    export AWS_REGION=eu-central-1
    export AWS_PROFILE=your-profile
    export OPENBI_S3_BUCKET=openbi-raw-123456789012
    python python/s3_operations.py

Read-only by default. Set OPENBI_S3_WRITE=1 to also upload/delete a
small test object.

Reference: https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError


def get_s3_client():
    region = os.environ.get("AWS_REGION") or "eu-central-1"
    return boto3.client("s3", region_name=region)


def describe_bucket(s3, name: str) -> None:
    """Print bucket metadata: versioning, encryption, lifecycle."""
    print(f"\n==> Bucket: {name}")

    try:
        info = s3.head_bucket(Bucket=name)
        print(f"    exists: yes ({info['ResponseMetadata']['HTTPHeaders'].get('x-amz-bucket-region', 'unknown region')})")
    except ClientError as exc:
        print(f"    exists: no ({exc.response['Error']['Code']})")
        return

    # Versioning
    try:
        versioning = s3.get_bucket_versioning(Bucket=name)
        print(f"    versioning: {versioning.get('Status', 'Disabled')}")
    except ClientError as exc:
        print(f"    versioning: unknown ({exc.response['Error']['Code']})")

    # Encryption
    try:
        enc = s3.get_bucket_encryption(Bucket=name)
        rules = enc["ServerSideEncryptionConfiguration"]["Rules"]
        algo = rules[0]["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"]
        print(f"    encryption: {algo}")
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ServerSideEncryptionConfigurationNotFoundError":
            print("    encryption: none (unencrypted)")
        else:
            print(f"    encryption: unknown ({exc.response['Error']['Code']})")

    # Public access block
    try:
        block = s3.get_public_access_block(Bucket=name)
        config = block["PublicAccessBlockConfiguration"]
        all_blocked = all([
            config.get("BlockPublicAcls"),
            config.get("BlockPublicPolicy"),
            config.get("IgnorePublicAcls"),
            config.get("RestrictPublicBuckets"),
        ])
        print(f"    public access blocked: {all_blocked}")
    except ClientError:
        print("    public access blocked: unknown")


def list_objects(s3, name: str, prefix: str = "", max_keys: int = 10) -> None:
    """List a few objects in the bucket."""
    print(f"\n==> Objects in {name} (prefix='{prefix}')")
    try:
        response = s3.list_objects_v2(
            Bucket=name,
            Prefix=prefix,
            MaxKeys=max_keys,
        )
    except ClientError as exc:
        print(f"    error: {exc.response['Error']['Code']}")
        return

    contents = response.get("Contents", [])
    if not contents:
        print("    (no objects)")
        return

    for obj in contents:
        key = obj["Key"]
        size_kb = obj["Size"] / 1024
        modified = obj["LastModified"]
        print(f"    {key}  ({size_kb:.1f} KB, {modified})")

    if response.get("IsTruncated"):
        print("    ... (more objects not shown)")


def optional_write_test(s3, bucket: str) -> None:
    """If OPENBI_S3_WRITE=1, upload and delete a small test object."""
    if os.environ.get("OPENBI_S3_WRITE") != "1":
        return

    key = f"__openbi-test/{datetime.now(timezone.utc).isoformat()}.txt"
    body = b"openbi-aws-cloud s3 write test\n"

    print(f"\n==> Write test: put_object {key}")
    s3.put_object(Bucket=bucket, Key=key, Body=body)
    print("    uploaded")

    print("==> Read back")
    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj["Body"].read().decode()
    print(f"    content: {content.strip()}")

    print("==> Generate presigned URL (60s)")
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=60,
    )
    print(f"    {url[:100]}...")

    print("==> Cleanup: delete_object")
    s3.delete_object(Bucket=bucket, Key=key)
    print("    deleted")


def main() -> int:
    s3 = get_s3_client()

    raw_bucket = os.environ.get("OPENBI_S3_BUCKET") or os.environ.get("OPENBI_S3_RAW_BUCKET")
    if not raw_bucket:
        print("Set OPENBI_S3_BUCKET to the raw bucket name (e.g. openbi-raw-123456789012)")
        print("Skipping live operations; demonstrating local-only patterns instead.")
        print("\nExample command:")
        print("  export OPENBI_S3_BUCKET=openbi-raw-123456789012")
        print("  python python/s3_operations.py")
        return 0

    describe_bucket(s3, raw_bucket)
    list_objects(s3, raw_bucket)
    optional_write_test(s3, raw_bucket)

    return 0


if __name__ == "__main__":
    sys.exit(main())
