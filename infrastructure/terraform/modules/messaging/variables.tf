variable "project_name" {
  type    = string
  default = "photoalbum"
}

variable "environment" {
  type = string
}

variable "raw_media_bucket_arn" {
  type        = string
  description = "ARN of the raw media S3 bucket, used to scope the SNS publish permission."
}
