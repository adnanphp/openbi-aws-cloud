# Secrets Manager

AWS Secrets Manager stores application secrets: database credentials,
API keys, tokens, anything that shouldn't be in a Kubernetes manifest or
a Git repository.

## Why not Kubernetes Secrets

Kubernetes Secrets are:
- Base64-encoded by default (not encrypted)
- Stored in etcd
- Not automatically rotated
- Versioned with the cluster, not the secret

They're fine for non-sensitive configuration but a poor choice for
actual secrets. The correct pattern is:

1. Secret lives in a dedicated secret store (Secrets Manager)
2. A controller (External Secrets Operator) reads it
3. The controller creates a Kubernetes Secret for the pod to mount
4. The pod sees a normal Secret but the value came from outside

## Secret naming convention

All OpenBI secrets live under a common prefix:
openbi/<env>/<purpose>

text

Examples:

| Purpose | Secret path | Contents |
| --- | --- | --- |
| Database credentials | `openbi/dev/db` | host, port, username, password |
| Redis auth token | `openbi/dev/redis` | password |
| Third-party API keys | `openbi/dev/api-keys` | JSON object with named keys |
| Email credentials | `openbi/dev/smtp` | host, port, username, password |

The prefix is scoped by environment (`dev`, `staging`, `prod`) so a
misconfigured operator can't accidentally read production secrets.

## The IRSA role

The `terraform/modules/secrets/` module creates an IRSA role that
External Secrets Operator assumes. The role's policy is scoped to
`openbi/dev/*` — ESO can only read secrets under that prefix.

The role:
- Has `secretsmanager:GetSecretValue`, `DescribeSecret`, `ListSecretVersionIds`
- Is granted `kms:Decrypt` only via Secrets Manager (`kms:ViaService` condition)
- Is assumed via IRSA by the `external-secrets/external-secrets` ServiceAccount

## How ESO uses the role
Pod (ServiceAccount: external-secrets)
│
│ mounted projected token
▼
AWS STS validates via OIDC
│
│ returns temporary credentials
▼
ESO reads secrets from Secrets Manager
│
│ creates/updates K8s Secret
▼
Application Pod mounts the K8s Secret

text

The ESO pod holds the AWS credentials; the application pod never sees
them. The application only sees the materialized Secret.

## Adding a new secret

1. Create the secret in Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name openbi/dev/my-service \
  --secret-string '{"api_key": "..."}'
Create an ExternalSecret in the target namespace:

yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-credentials
  namespace: openbi
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-service-credentials
  data:
    - secretKey: api_key
      remoteRef:
        key: openbi/dev/my-service
        property: api_key
Mount it in the pod:

yaml
spec:
  containers:
    - name: my-service
      envFrom:
        - secretRef:
            name: my-service-credentials
Rotation
RDS master password: rotated automatically by RDS
(manage_master_user_password = true)

Other secrets: no automatic rotation configured in A9. Rotation
requires a Lambda function with a rotation algorithm. Documented as a
future enhancement.

For secrets that need periodic rotation (API tokens, service account
keys), the pattern is:

Rotate in the source system

Update the value in Secrets Manager

ESO picks up the new value at the next refresh interval

Pods restart or reload to pick up the new value

What maps to GCP
AWS	GCP
Secrets Manager	Secret Manager
External Secrets Operator	External Secrets Operator
IRSA	Workload Identity
Secret name prefix	Secret name prefix
Rotation via Lambda	Rotation via Cloud Functions
CloudTrail access logs	Cloud Audit Logs
What transfers directly:

The store-and-sync pattern (ESO works on both clouds)

Secret naming conventions

Least-privilege access via workload identity

Refresh intervals and materialization into Kubernetes Secrets

The IRSA / Workload Identity trust mechanism (similar in shape)

What does not transfer:

The aws secretsmanager CLI vs gcloud secrets CLI

The IAM policy structure for reading secrets

The rotation Lambda implementation (would be a Cloud Function on GCP)

Verification status
Not verified against real AWS. The Terraform module is statically
validated. The ExternalSecret manifests are syntactically correct YAML
but reference secrets that don't exist yet. See verification.md.
