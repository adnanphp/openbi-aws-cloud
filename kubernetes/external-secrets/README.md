# External Secrets Operator

External Secrets Operator (ESO) syncs secrets from AWS Secrets Manager
into Kubernetes Secrets. It is the mechanism we use so that no secret
material ever lives in this repository or in plain Kubernetes YAML.

## How it works
AWS Secrets Manager
│
│ ESO reads via IRSA
▼
External Secrets Operator (running in cluster)
│
│ creates/updates
▼
Kubernetes Secret
│
│ mounted by
▼
Application Pod

text

The ESO pod assumes an IAM role via IRSA, which grants it read access to
Secrets Manager. It creates standard Kubernetes Secrets that pods can
mount as normal.

## Installation

ESO is installed via Helm (not included in this repo; see the official
chart):

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
The IRSA role for ESO is created in a future phase (A9, when Secrets
Manager is set up).

Usage (once installed and configured)
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
  data:
    - secretKey: password
      remoteRef:
        key: openbi/dev/db
        property: password
This manifest is a template — the actual ExternalSecret resources are
created in the phases that need them (A6 for RDS, A9 for the general
secret store).
