# OpenBI application manifests (placeholder)

This directory will hold the full OpenBI application manifests adapted
for EKS:

- FastAPI deployment + service
- Superset deployment + service
- Postgres connection (via RDS, not a local pod)
- Redis connection (via ElastiCache, not a local pod)
- Kafka connection (via MSK, or replaced by SQS)
- MinIO replaced by S3
- Loki replaced by CloudWatch Logs

These are created in Phase A10 (Kubernetes manifests). For now, the
directory exists as a placeholder.

## A minimal smoke test

To verify the cluster accepts workloads, a trivial deployment can be
applied after the cluster is up:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  namespace: openbi
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: public.ecr.aws/nginx/nginx:stable
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello
  namespace: openbi
spec:
  selector:
    app: hello
  ports:
    - port: 80
      targetPort: 80
Applied via:

bash
kubectl apply -f kubernetes/openbi-app/hello.yaml
kubectl -n openbi get pods
This isn't included as a real manifest because it isn't part of the
OpenBI application — it's a diagnostic tool.
