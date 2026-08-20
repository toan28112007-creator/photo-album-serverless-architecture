variable "project_name" {
  type        = string
  description = "Short project prefix used in all resource names."
  default     = "photoalbum"
}

variable "environment" {
  type        = string
  description = "Deployment environment, e.g. dev, prod."
}

variable "suffix" {
  type        = string
  description = "Random/account-specific suffix to keep bucket names globally unique."
}

variable "upload_topic_arn" {
  type        = string
  description = "ARN of the SNS topic that receives S3 ObjectCreated events (from modules/messaging)."
}

variable "topic_policy_dependency" {
  type        = any
  description = "Pass the SNS topic policy resource here to enforce correct apply ordering (S3 needs permission to publish before the notification is attached)."
}
