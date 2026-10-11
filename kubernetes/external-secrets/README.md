# External Secrets Operator

External Secrets Operator (ESO) syncs secrets from AWS Secrets Manager
into Kubernetes Secrets. It's the mechanism we use so that no secret
material ever lives in this repository or in plain Kubernetes YAML.

## How it works
AWS Secrets Manager
│ (secret: openbi/dev/db)
│
│ ESO reads via IRSA role
▼
External Secrets Operator (Deployment in external-secrets namespace)
│
│ creates/updates a Kubernetes Secret named per the ExternalSecret
▼
Kubernetes Secret (in the target namespace)
│
│ mounted by
▼
Application Pod

text

Pods consume standard Kubernetes Secrets. They never touch AWS APIs,
never hold credentials, and never see the raw secret value in their
environment.

## Installation

Installed via Helm. Replace `ROLE_ARN` with the output from Terraform:

```bash
# Get the ESO IRSA role ARN
cd terraform/environments/dev
ROLE_ARN=$(terraform output -raw eso_role_arn)

# Add the Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.name=external-secrets \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
Verification
bash
kubectl -n external-secrets get pods
kubectl -n external-secrets get deployment
The ESO Deployment (and its webhook) should be running.

Usage
1. Create a ClusterSecretStore (once per cluster)
The ClusterSecretStore tells ESO how to reach AWS. See
cluster-secret-store.yaml in this directory.

2. Create an ExternalSecret (once per secret, per namespace)
yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: openbi-db-credentials
  namespace: openbi
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: openbi-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: host
      remoteRef:
        key: openbi/dev/db
        property: host
    - secretKey: port
      remoteRef:
        key: openbi/dev/db
        property: port
    - secretKey: username
      remoteRef:
        key: openbi/dev/db
        property: username
    - secretKey: password
      remoteRef:
        key: openbi/dev/db
        property: password
3. Mount the secret in a Pod
yaml
spec:
  containers:
    - name: app
      envFrom:
        - secretRef:
            name: openbi-db-credentials
Secret naming convention
All OpenBI secrets live under a common prefix:

text
openbi/dev/<purpose>
Examples:

openbi/dev/db — database connection details

openbi/dev/redis — Redis auth token

openbi/dev/api-keys — third-party API keys

openbi/dev/smtp — email credentials

The IRSA role created in terraform/modules/secrets/ is scoped to this
prefix. ESO can only read secrets that start with openbi/dev/.

Refresh interval
refreshInterval: 1h means ESO re-reads the secret from AWS every hour.
If the value changes in Secrets Manager, the Kubernetes Secret is
updated within an hour. Pods that mount the secret see the new value
after their next restart (or via a reloader).

What's not in A9
Secret rotation (customer-managed). Rotation requires Lambda
functions. RDS manages its own password rotation; other secrets would
need a rotation Lambda. Out of scope for A9.

Actual production secrets. Real credentials are added when the
services that need them exist (A10).

Alerting on secret access anomalies. Would use CloudTrail +
CloudWatch metric filters. Documented as a future enhancement.

What maps to GCP
AWS	GCP
Secrets Manager	Secret Manager
External Secrets Operator	External Secrets Operator
IRSA	Workload Identity
Secret prefix openbi/dev/	Secret path openbi-dev-
Automatic rotation (Lambda)	Automatic rotation (Cloud Functions)
KMS-encrypted secrets	CMEK-encrypted secrets
CloudTrail access logs	Cloud Audit Logs
