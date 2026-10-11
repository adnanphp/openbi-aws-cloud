# ALB — Application Load Balancer and Ingress

The AWS Load Balancer Controller turns Kubernetes `Ingress` resources
into real AWS Application Load Balancers. This document explains the
integration and the design decisions.

## Why not a static ALB in Terraform?

There are two approaches:

**Approach A — Terraform creates an ALB, K8s routes through it.**
- Terraform owns the ALB lifecycle
- The ALB exists regardless of what's running in the cluster
- Adding a new service requires editing Terraform

**Approach B — K8s Ingress resources create ALBs on demand.**
- Kubernetes owns the ALB lifecycle
- Delete the Ingress → ALB is deleted
- Adding a new service requires only a new Ingress

**OpenBI uses Approach B.** The controller reconciles Kubernetes state
into AWS state. This is the modern pattern and the one that makes
"In Kubernetes" and "on AWS" feel like one system.

## Architecture
User (browser or client)
│
│ HTTP/HTTPS
▼
Application Load Balancer (created by the controller)
│
├─ Listener: 80 → target group: openbi/fastapi
├─ Listener: 443 (if cert present) → target group: openbi/superset
└─ ...
│
│ routes to pod IPs (target-type: ip)
▼
EKS cluster (private subnets)

text

## Design decisions

### Target type: `ip` (not `instance`)

Two modes:

- **`instance`** — the ALB targets EC2 node instances and routes via
  NodePorts. Requires the Service to be `NodePort`.
- **`ip`** — the ALB targets pod IPs directly. Requires the VPC CNI
  (which we have) and the Service to be `ClusterIP`.

`ip` is more efficient — one hop instead of two, and it avoids NodePort
port allocation. We use `ip`.

### Internal vs. internet-facing

The `alb.ingress.kubernetes.io/scheme` annotation controls this:

- **`internal`** — the ALB lives in private subnets. Reachable only from
  within the VPC.
- **`internet-facing`** — the ALB lives in public subnets. Reachable
  from the internet.

OpenBI's dev Ingresses default to `internal`. Production would use
`internet-facing` for public APIs. The choice is per-Ingress, not per
cluster.

### Group name: sharing one ALB

By default, every Ingress gets its own ALB. The
`alb.ingress.kubernetes.io/group.name` annotation merges Ingresses into
one ALB with path-based or host-based routing.

**Why share:** fewer ALBs to manage, one set of health checks, one TLS
certificate. For a data platform with FastAPI, Superset, and other
services behind the same domain, this is the right design.

### HTTPS via ACM

HTTPS requires a certificate. AWS Certificate Manager (ACM) provides
free certificates, but validation requires a domain you control.

The ALB module handles this optionally:
- **No domain configured** — no certificate, HTTP only. Fine for a lab.
- **Domain configured + Route53 zone** — the module creates the ACM
  certificate and validates it via DNS records.
- **Domain configured, no Route53** — the module creates the
  certificate; you validate manually via DNS or email.

Once the certificate exists, Ingress annotations connect it:
```yaml
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
alb.ingress.kubernetes.io/ssl-redirect: "443"
IRSA role
The controller assumes an IAM role via IRSA to call the ELB, EC2, WAF,
and Shield APIs. The trust policy is scoped to the specific
ServiceAccount (kube-system/aws-load-balancer-controller).

The AWS-published AWSLoadBalancerControllerIAMPolicy is attached
rather than an inlined copy. AWS updates this policy as the controller
gains features; using the managed policy means you get those updates
automatically.

The reconciliation loop
text
kubectl apply -f ingress.yaml
    │
    │  K8s API stores the Ingress
    ▼
Controller watches for Ingress changes
    │
    │  controller sees new Ingress
    ▼
Controller calls:
  - elasticloadbalancing:CreateLoadBalancer
  - elasticloadbalancing:CreateTargetGroup
  - elasticloadbalancing:CreateListener
  - ec2:DescribeSubnets (to determine where to place the ALB)
  - ec2:AuthorizeSecurityGroupIngress (for ALB → pod traffic)
  - ...and more
    │
    ▼
ALB exists, routes to pods

Deleting the Ingress:
  - controller deletes the ALB, target groups, listeners
Example Ingress
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: openbi-api
  namespace: openbi
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/group.name: openbi
spec:
  ingressClassName: alb
  rules:
    - host: api.openbi.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fastapi
                port:
                  number: 8000
The ingressClassName: alb line is critical — it tells Kubernetes to
route this Ingress to the ALB controller (not another Ingress controller
like Traefik or nginx).

Multiple Ingress controllers
Clusters often run more than one Ingress controller. The
ingressClassName field determines which one handles a given Ingress.

OpenBI locally uses Traefik. In EKS, Traefik would still work (it can
create a LoadBalancer Service that provisions an NLB), but the more
common pattern on AWS is the AWS Load Balancer Controller + ALB.

For this repo, we use the AWS Load Balancer Controller as the
Kubernetes-native path. The Traefik-based path is documented as an
alternative.

What's not in A8
The actual Ingresses for OpenBI services. Those come in A10,
when the OpenBI Deployments and Services exist.

DNS records. Pointing a domain at the ALB requires Route53
records, which need a registered domain. Out of scope for the lab.

WAF integration. ALBs can be protected by AWS WAF, but that's an
application-security concern, not infrastructure.

What maps to GCP
AWS	GCP
Application Load Balancer	HTTP(S) Load Balancer
AWS Load Balancer Controller	GKE Ingress (built-in)
Ingress (Kubernetes)	Ingress (Kubernetes)
Target groups	Backend services
ACM certificate	Google-managed certificate
Route53 validation	Cloud DNS
target-type: ip	NEG (Network Endpoint Group)
group.name annotation	Backend service sharing
What transfers directly:

The Kubernetes Ingress API (identical)

The controller reconciliation pattern (GKE has this built in)

Path-based and host-based routing

HTTPS termination at the LB

Health checks

Grouping multiple services behind one LB

What does not transfer:

The specific annotations (alb.ingress.kubernetes.io/*)

The controller itself (GKE's is built into the platform)

ACM (vs. Google-managed certificates)

ALB vs. Google Cloud Load Balancer feature parity

Verification status
Not verified against real AWS. The Terraform module is statically
validated. The Kubernetes manifests are syntactically correct YAML. The
Helm install commands are documented but have not been executed. See
verification.md.
