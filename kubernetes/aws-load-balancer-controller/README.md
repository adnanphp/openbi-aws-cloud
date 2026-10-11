# AWS Load Balancer Controller

The AWS Load Balancer Controller watches Kubernetes `Ingress` resources
and provisions Application Load Balancers (ALBs) that route to your
services.

## How it works
Kubernetes Ingress resource (ingressClassName: alb)
│
│ controller watches
▼
AWS Load Balancer Controller (Deployment in kube-system)
│
│ calls AWS APIs using its IRSA role
▼
Application Load Balancer + Target Groups + Listeners
│
│ routes to
▼
Kubernetes Services (pods, via IP target type)

text

The controller is what turns a declarative Kubernetes Ingress into a
real AWS load balancer. It reconciles state — if you delete the Ingress,
the ALB is deleted.

## IRSA role

The controller needs an IAM role (created by `terraform/modules/alb/`)
with the AWS-published `AWSLoadBalancerControllerIAMPolicy`. The role is
assumed via IRSA by the `kube-system/aws-load-balancer-controller`
ServiceAccount.

## Installation

Install via Helm. Replace the role ARN with the output from Terraform:

```bash
# Get the role ARN
cd terraform/environments/dev
ROLE_ARN=$(terraform output -raw alb_controller_role_arn)

# Get the VPC ID and cluster name
VPC_ID=$(terraform output -raw vpc_id)
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
AWS_REGION=eu-central-1

# Add the Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID
Verifying the installation
bash
# Controller pod should be running
kubectl -n kube-system get deployment aws-load-balancer-controller
kubectl -n kube-system logs -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20
Creating an Ingress
Once installed, an Ingress with ingressClassName: alb triggers ALB
provisioning. See ../ingress/examples.yaml for examples.

Key annotations:

Annotation	Effect
alb.ingress.kubernetes.io/scheme	internet-facing or internal
alb.ingress.kubernetes.io/target-type	ip (pod IPs) or instance (NodePort)
alb.ingress.kubernetes.io/listen-ports	Which ports to listen on (e.g. [{"HTTP":80}] or with HTTPS)
alb.ingress.kubernetes.io/certificate-arn	ACM certificate ARN for HTTPS
alb.ingress.kubernetes.io/ssl-redirect	Redirect HTTP to HTTPS
alb.ingress.kubernetes.io/healthcheck-path	Path used for target group health checks
Cleanup
bash
helm uninstall aws-load-balancer-controller -n kube-system
Deleting the controller does NOT delete the ALBs it created — those are
tied to their Ingress resources. Delete the Ingresses first if you want
the ALBs gone.
