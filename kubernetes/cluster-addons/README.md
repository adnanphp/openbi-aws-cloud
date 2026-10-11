# Cluster Add-ons

DaemonSets that run on every node and provide cluster-wide capabilities:

- **Fluent Bit** — ships container logs to CloudWatch Logs
- **CloudWatch agent** — collects Container Insights metrics

Both are AWS-managed components that run as standard Kubernetes
DaemonSets. They exist to close the gap between "pods running" and "pods
observable."

## Applying

```bash
kubectl apply -f kubernetes/cluster-addons/
Prerequisites
The log groups from Phase A9 exist (/aws/openbi/fastapi, etc.)

The cluster's IRSA role for the CloudWatch agent exists (created
below in cloudwatch-agent.yaml as a ServiceAccount annotation —
replace the placeholder ARN with the real one created by Terraform)

Fluent Bit vs. CloudWatch agent
They are complementary:

Component	What it does
Fluent Bit	Reads container stdout from /var/log/pods/, ships to CloudWatch Logs
CloudWatch agent	Reads node/pod metrics from kubelet, ships to CloudWatch Metrics (Container Insights)
Fluent Bit handles logs. CloudWatch agent handles metrics. Both are
required for full observability.
