# CloudWatch — Logs, Metrics, Alarms, Dashboards

CloudWatch is AWS's observability service. In OpenBI it plays three
roles: log aggregation, metric storage, and alerting.

## Log groups

One log group per service:
/aws/openbi/fastapi
/aws/openbi/superset
/aws/openbi/cluster-autoscaler
/aws/openbi/external-secrets
/aws/openbi/aws-load-balancer-controller

text

Retention is set to 14 days by default (configurable). Setting
retention is important — CloudWatch defaults to "never expire," which
grows indefinitely.

Services write to their log group via a DaemonSet (Fluent Bit) that
ships container stdout to CloudWatch. That DaemonSet is installed in
Phase A10.

## Alarms

Three alarms, each targeting a signal that requires action:

| Alarm | Fires when | Why |
| --- | --- | --- |
| `openbi-dev-rds-cpu-high` | RDS CPU > 80% for 10 min | The DB is the bottleneck |
| `openbi-dev-dlq-not-empty` | DLQ has any message | Something is failing |
| `openbi-dev-alb-5xx-high` | ALB 5xx rate > 5% for 5 min | User-facing errors |

Every alarm publishes to the same SNS topic. Subscribers (email, Slack,
PagerDuty) are added separately — putting email addresses in Terraform
would be an anti-pattern (credentials and addresses should not live in
code).

**Why only three alarms?** Alarm fatigue is real. If everything is
critical, nothing is. These three cover the most important failure
modes for a data platform:
- Compute/DB saturation
- Data pipeline failures
- User-facing errors

More alarms can be added as the platform matures.

## Dashboard

One dashboard, `<name_prefix>-platform`, with panels grouped by layer:

| Row | Panels |
| --- | --- |
| Title | Region, cluster name |
| EKS | Node count, running pod count |
| RDS | CPU, connections, free storage |
| SQS | Main queue depth, DLQ depth |
| Logs | Recent errors across all services |

The dashboard is provisioned as code (`aws_cloudwatch_dashboard`) so it
is version-controlled and consistent across environments.

## Container Insights

The EKS cluster is monitored by **CloudWatch Container Insights**, which
provides cluster and pod-level metrics (CPU, memory, network, disk).
Container Insights is installed as a DaemonSet (the CloudWatch agent)
plus a few extra components. Installation is part of the OpenBI
Kubernetes manifests (Phase A10).

Container Insights metrics appear in the dashboard's EKS panels.

## Log insights queries

CloudWatch Logs Insights is a SQL-like query language for logs. A useful
default is the "recent errors" panel in the dashboard:
SOURCE '/aws/openbi/fastapi'
| SOURCE '/aws/openbi/superset'
| fields @timestamp, @logStream, @message
| filter @message like /ERROR|error|Error/
| sort @timestamp desc
| limit 50

text

This query spans multiple log groups and finds anything that looks like
an error in the last 15 minutes.

## What maps to GCP

| AWS | GCP |
| --- | --- |
| CloudWatch Logs | Cloud Logging |
| CloudWatch Metrics | Cloud Monitoring |
| CloudWatch Alarms | Alerting Policies |
| CloudWatch Dashboards | Cloud Monitoring Dashboards |
| CloudWatch Logs Insights | Logging Query Language |
| Container Insights | GKE system metrics + Managed Prometheus |
| SNS for alarm notifications | Notification channels |
| Log group retention | Log bucket retention |

**What transfers directly:**

- Structured logs with service-level separation
- Alerting on saturation, failures, and error rates
- Dashboards as code
- Query languages for log analysis
- Container-level metrics from a DaemonSet

**What does not transfer:**

- Log Insights query syntax
- The exact metric namespaces and dimensions
- The `aws_cloudwatch_metric_alarm` resource semantics

## Verification status

**Not verified against real AWS.** The Terraform module is statically
validated. Alarms, dashboards, and log groups are created as code but
have not been deployed. See `verification.md`.
