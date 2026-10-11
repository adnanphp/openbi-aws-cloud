# Outputs from the CloudWatch module.

output "service_log_group_names" {
  description = "Map of service name → log group name"
  value = {
    for name, lg in aws_cloudwatch_log_group.services :
    name => lg.name
  }
}

output "service_log_group_arns" {
  description = "Map of service name → log group ARN"
  value = {
    for name, lg in aws_cloudwatch_log_group.services :
    name => lg.arn
  }
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic that receives alarm notifications"
  value       = aws_sns_topic.alarms.arn
}
