# Kubernetes Manifests

All Kubernetes resources for running OpenBI on EKS.

## Application order

Apply in this order. Each step depends on the previous one.

```bash
# 1. Namespaces
kubectl apply -f kubernetes/namespaces/

# 2. Cluster add-ons (DaemonSets for observability)
kubectl apply -f kubernetes/cluster-addons/

# 3. Cluster-level controllers (installed via Helm, not kubectl)
#    See the README in each directory:
#    - aws-load-balancer-controller/
#    - external-secrets/
#    - cluster-autoscaler/

# 4. External Secrets Operator's ClusterSecretStore
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml

# 5. OpenBI application manifests
kubectl apply -k kubernetes/openbi-app/overlays/dev
Directory layout
Directory	Purpose
namespaces/	The openbi, monitoring, logging namespaces
cluster-addons/	Fluent Bit (logs) and CloudWatch agent (metrics) DaemonSets
cluster-autoscaler/	The Kubernetes Cluster Autoscaler Deployment
aws-load-balancer-controller/	Install docs for the ALB controller
external-secrets/	Install docs + ClusterSecretStore + ExternalSecret examples
ingress/	Example Ingress resources (references; real ones in openbi-app)
openbi-app/	Kustomize base + overlays for the OpenBI workloads
What each controller does
Controller	Purpose
Cluster Autoscaler	Scales the spot node group when pods are pending
AWS Load Balancer Controller	Provisions ALBs when Ingresses are applied
External Secrets Operator	Syncs secrets from AWS Secrets Manager
These are installed via Helm because they're third-party components with
their own release cadence. The OpenBI application manifests are
Kustomize because they change together.

Verification
bash
kubectl -n openbi get all
kubectl -n openbi get ingress
kubectl -n openbi get externalsecret
kubectl get pods -n kube-system | grep -E "autoscaler|load-balancer"
kubectl get pods -n external-secrets
