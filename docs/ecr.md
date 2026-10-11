# ECR — Container Image Registry

The OpenBI container images live in Amazon ECR so the EKS cluster can
pull them. This document explains the registry design, the image flow,
and the operational commands.

## Why ECR

Every container image must come from somewhere the cluster can reach.
Options:

| Option | Pros | Cons |
| --- | --- | --- |
| Public Docker Hub | Free, no setup | Rate limits, no privacy, no scan |
| Private registry on EC2 | Full control | You operate it |
| **Amazon ECR** | Managed, private, scanned, IAM-integrated | AWS-specific |

ECR is the natural choice for an AWS deployment. It integrates with IAM
(the same roles used everywhere else), it scans images on push for known
CVEs, and it has no rate limits.

## Design

### Single repository, tagged images

One ECR repository (`openbi`) holds every OpenBI image. Images are
distinguished by tag prefix:
openbi:fastapi-v0.1.0
openbi:fastapi-latest
openbi:superset-3.1.3
openbi:minio-latest

text

**Why a single repo?** Fewer repositories to manage, fewer lifecycle
policies, and images of the same project stay together. Monorepos
commonly work this way; separate repos make more sense for
independently-versioned projects.

### Lifecycle policy

Two rules:

1. **Keep last 10 tagged images.** Older tags are automatically expired.
   This bounds storage cost and prevents image sprawl.
2. **Delete untagged images after 7 days.** Untagged images are
   typically intermediate build layers. They have no value after a
   week.

Storage cost is small (`~$0.10/GB/month`) but unbounded growth is a
smell.

### Scan on push

Every pushed image is scanned for known CVEs. The scan is free for the
basic scanner (which uses the open-source Clair database) and runs
automatically. Results are visible in the ECR console and via the API:

```bash
aws ecr describe-image-scan-findings \
  --repository-name openbi \
  --image-id imageTag=fastapi-v0.1.0
Repository policy
The repository is private. An explicit DenyPublicAccess statement
denies pull permissions to any principal outside the account. This is
defense-in-depth — ECR is private by default, but an explicit deny
documents intent and survives accidental future policy changes.

Image flow
text
Developer's laptop
      │
      │  docker build
      ▼
Local image (e.g. openbi-fastapi:latest)
      │
      │  docker tag → ECR URL
      ▼
ECR-tagged image (e.g. 123456789012.dkr.ecr.eu-central-1.amazonaws.com/openbi:fastapi-v0.1.0)
      │
      │  docker push
      ▼
ECR repository
      │
      │  imagePull (from EKS kubelet, using node IAM role)
      ▼
EKS worker node
      │
      │  containers run
      ▼
OpenBI pods
The EKS node role (created in the IAM module) already has
AmazonEC2ContainerRegistryReadOnly, so nodes can pull images without
additional configuration.

Operational commands
All commands assume AWS_REGION and credentials are configured.

Authenticate Docker to ECR
bash
aws ecr get-login-password --region eu-central-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.eu-central-1.amazonaws.com
The login token is valid for 12 hours.

List repositories
bash
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `openbi`)]'
List images in the OpenBI repository
bash
aws ecr list-images --repository-name openbi
Build and push all OpenBI images
bash
./scripts/build-and-push.sh \
  123456789012.dkr.ecr.eu-central-1.amazonaws.com/openbi \
  v0.1.0
The script:

Authenticates Docker to ECR

For each OpenBI service, builds the image if it doesn't exist locally

Tags it as <ecr-repo>:<service>-<suffix>

Pushes it

Python SDK examples
python/ecr_operations.py shows the boto3 equivalents:

bash
python python/ecr_operations.py
It lists repositories with the openbi prefix and shows the images in
each. Read-only — no create or delete operations.

Verification status
Not verified against real AWS. The Terraform module is statically
validated (terraform validate) and the scripts are correct as written
but have not been executed against a real ECR repository. See
verification.md.

Cost
Item	Cost
Storage	$0.10/GB/month
Data transfer within region	Free
Data transfer out to internet	$0.09/GB after 100 GB/month free
Vulnerability scanning (basic)	Free
For a lab with 5 images of ~200 MB each, storage is ~$0.10/month.
Effects on the overall cost estimate are negligible.

What maps to GCP
AWS	GCP
ECR	Artifact Registry
aws ecr get-login-password	gcloud auth configure-docker
Image scanning (basic)	Container Analysis
Lifecycle policies	Cleanup policies
Repository policies	IAM bindings on the registry
The image flow is identical — build locally, tag for the registry,
push, pull from the cluster. The commands change; the concept does not.
