"""RDS PostgreSQL connection examples via boto3 and psycopg2.

Shows the two authentication paths an OpenBI pod could use:

  1. Password from Secrets Manager (fallback)
  2. IAM database authentication (preferred; no stored password)

Both are demonstrated. The script only runs the connection attempts if
OPENBI_RDS_ENDPOINT is set; otherwise it prints the code paths as
documentation.

To use against real RDS:

    export AWS_REGION=eu-central-1
    export OPENBI_RDS_ENDPOINT=openbi-dev-postgres.xxxxx.eu-central-1.rds.amazonaws.com
    export OPENBI_RDS_DB=openbi
    export OPENBI_RDS_USER=openbiadmin
    export OPENBI_RDS_SECRET_ARN=arn:aws:secretsmanager:...
    python python/rds_connection.py

Requires:
    pip install boto3 psycopg2-binary
"""

from __future__ import annotations

import json
import os
import sys

import boto3


def get_secret_password(secret_arn: str) -> str:
    """Retrieve the master password from Secrets Manager."""
    client = boto3.client(
        "secretsmanager",
        region_name=os.environ.get("AWS_REGION", "eu-central-1"),
    )
    response = client.get_secret_value(SecretId=secret_arn)
    secret = json.loads(response["SecretString"])
    return secret["password"]


def generate_iam_auth_token(endpoint: str, port: int, user: str) -> str:
    """Generate a temporary IAM auth token (valid 15 minutes).

    The token is a signed request used as the password when connecting.
    The DB user must have been granted the rds_iam role:

        GRANT rds_iam TO openbiadmin;
    """
    client = boto3.client(
        "rds",
        region_name=os.environ.get("AWS_REGION", "eu-central-1"),
    )
    return client.generate_db_auth_token(
        DBHostname=endpoint,
        Port=port,
        DBUsername=user,
    )


def connect_with_password(endpoint: str, port: int, db: str, user: str, password: str):
    """Connect using a password (from Secrets Manager)."""
    import psycopg2

    return psycopg2.connect(
        host=endpoint,
        port=port,
        dbname=db,
        user=user,
        password=password,
        sslmode="require",
    )


def connect_with_iam(endpoint: str, port: int, db: str, user: str, token: str):
    """Connect using an IAM auth token as the password."""
    import psycopg2

    return psycopg2.connect(
        host=endpoint,
        port=port,
        dbname=db,
        user=user,
        password=token,
        sslmode="require",
    )


def main() -> int:
    endpoint = os.environ.get("OPENBI_RDS_ENDPOINT")
    if not endpoint:
        print("Set OPENBI_RDS_ENDPOINT to try a real connection.")
        print("\nThe two authentication paths are:")
        print("  1. Password from Secrets Manager (see get_secret_password)")
        print("  2. IAM auth token (see generate_iam_auth_token)")
        print("\nBoth use sslmode=require for TLS.")
        print("\nFor production pods, prefer IAM auth: no password to rotate,")
        print("tokens expire in 15 minutes, and access is governed by the pod's")
        print("IRSA role rather than a stored credential.")
        return 0

    db = os.environ.get("OPENBI_RDS_DB", "openbi")
    user = os.environ.get("OPENBI_RDS_USER", "openbiadmin")
    port = int(os.environ.get("OPENBI_RDS_PORT", "5432"))
    secret_arn = os.environ.get("OPENBI_RDS_SECRET_ARN")

    if not secret_arn:
        print("Set OPENBI_RDS_SECRET_ARN to test password auth.")
        return 1

    print(f"==> Connecting to {endpoint}:{port}/{db} as {user}")

    print("\n==> Path 1: password from Secrets Manager")
    password = get_secret_password(secret_arn)
    try:
        conn = connect_with_password(endpoint, port, db, user, password)
        with conn.cursor() as cur:
            cur.execute("SELECT version()")
            version = cur.fetchone()[0]
            print(f"    connected: {version[:60]}")
        conn.close()
    except Exception as exc:
        print(f"    failed: {exc}")

    print("\n==> Path 2: IAM database auth token")
    token = generate_iam_auth_token(endpoint, port, user)
    print(f"    token: {token[:50]}...")
    try:
        conn = connect_with_iam(endpoint, port, db, user, token)
        with conn.cursor() as cur:
            cur.execute("SELECT current_user, current_database()")
            row = cur.fetchone()
            print(f"    connected: user={row[0]} db={row[1]}")
        conn.close()
    except Exception as exc:
        print(f"    failed: {exc}")
        print("    (If the DB user does not have rds_iam role, run: GRANT rds_iam TO openbiadmin;)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
