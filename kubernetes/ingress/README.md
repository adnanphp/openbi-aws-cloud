
Ingress
Example Ingress resources that the AWS Load Balancer Controller turns
into real ALBs.

Prerequisites
The AWS Load Balancer Controller is installed (see
../aws-load-balancer-controller/README.md)

The target Services exist in the cluster (they don't yet — the
OpenBI manifests come in Phase A10)

For HTTPS: an ACM certificate exists (set domain_name in the ALB
module and re-apply Terraform)

Files
File	Purpose
examples.yaml	Three example Ingresses: HTTP-only, HTTPS, multi-service
Key annotations
alb.ingress.kubernetes.io/scheme: internal — the ALB is only
reachable inside the VPC. Use internet-facing for public access.

alb.ingress.kubernetes.io/target-type: ip — routes directly to pod
IPs. More efficient than instance (which goes through NodePorts).

alb.ingress.kubernetes.io/listen-ports — which ports the ALB
listens on. [{"HTTP":80}] for HTTP-only; add HTTPS with a
certificate ARN.

alb.ingress.kubernetes.io/group.name — Ingresses with the same
value share one ALB. Used for cost reduction and path-based routing.

What this demonstrates
Kubernetes Ingress → AWS ALB provisioning (declarative → managed)

Path-based routing across multiple services behind one ALB

HTTP → HTTPS redirect

Internal vs. internet-facing load balancers

Target type selection (ip vs instance)

What's not here
The actual Services these Ingresses point to (fastapi, superset) don't
exist in the cluster yet. They're created in Phase A10 along with the
rest of the OpenBI application manifests. These Ingress resources are
documentation of the pattern.
