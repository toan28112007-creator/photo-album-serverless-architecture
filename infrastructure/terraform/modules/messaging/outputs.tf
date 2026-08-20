output "topic_arn" {
  value = aws_sns_topic.upload_events.arn
}

output "topic_policy" {
  value       = aws_sns_topic_policy.upload_events_policy
  description = "Pass this into the storage module's topic_policy_dependency to sequence the apply correctly."
}

output "image_queue_arn" {
  value = aws_sqs_queue.image_queue.arn
}

output "image_queue_url" {
  value = aws_sqs_queue.image_queue.id
}

output "video_queue_arn" {
  value = aws_sqs_queue.video_queue.arn
}

output "video_queue_url" {
  value = aws_sqs_queue.video_queue.id
}

output "image_dlq_arn" {
  value = aws_sqs_queue.image_dlq.arn
}

output "video_dlq_arn" {
  value = aws_sqs_queue.video_dlq.arn
}
