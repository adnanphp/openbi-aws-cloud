# Outputs from the SQS module.
#
# The queue URLs and ARNs are consumed by:
#   - IRSA roles granting pods producer/consumer access
#   - Application configuration (env vars pointing at the queues)
#   - S3 event notifications (added in a later phase)

output "main_queue_url" {
  description = "URL of the main events queue"
  value       = aws_sqs_queue.main.id
}

output "main_queue_arn" {
  description = "ARN of the main events queue"
  value       = aws_sqs_queue.main.arn
}

output "main_queue_name" {
  description = "Name of the main events queue"
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL of the dead-letter queue"
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue"
  value       = aws_sqs_queue.dlq.name
}
