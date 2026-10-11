# AWS Load Balancer Controller

The AWS Load Balancer Controller watches Kubernetes `Ingress` resources
and provisions Application Load Balancers (ALBs) that route to your
services. It is the mechanism that lets a Kubernetes Ingress in this
cluster become a real AWS-managed load balancer.

## How it works
Kubernetes Ingress resource
│
│ controller watches
▼
AWS Load Balancer Controller
│
│ creates via AWS API
▼
Application Load Balancer + Target Groups
│
│ routes traffic to
▼
Kubernetes Services (pods)

text

## Installation

Installed via Helm in a future phase (A8). The reason it's listed here
already is that the IRSA role it uses (see below) is created once and
referenced many times.

## IRSA role

The controller needs an IAM role to create ALBs, target groups, and
modify security groups. The policy is AWS's published
`AWSLoadBalancerControllerIAMPolicy`.

**Setup** (in a future phase): create the IRSA role, install the
controller via Helm, annotate its ServiceAccount with the role ARN.

## What this repo will contain

Once Phase A8 is complete, this directory will hold:

- The IRSA role trust policy for the controller
- The Helm values file used for the install
- `IngressRoute` or `Ingress` examples showing how OpenBI services are
  exposed

For now, only this README exists, documenting the planned approach.
