variable "project_name" {
  type    = string
  default = "photoalbum"
}

variable "environment" {
  type = string
}

variable "lambda_role_arn" {
  type        = string
  description = "IAM role ARN for Lambda execution. On AWS Academy Learner Lab, set this to the pre-existing LabRole ARN — see README."
}

variable "image_processor_zip_path" {
  type    = string
  default = "../../../src/lambda/image-processor/build/image-processor.zip"
}

variable "app_api_zip_path" {
  type    = string
  default = "../../../src/lambda/app-api/build/app-api.zip"
}

variable "image_queue_arn" {
  type = string
}

variable "raw_media_bucket_name" {
  type = string
}

variable "derivatives_bucket_name" {
  type = string
}

variable "metadata_table_name" {
  type = string
}

variable "video_queue_name" {
  type = string
}

variable "video_queue_backlog_threshold" {
  type        = number
  default     = 10
  description = "Number of visible messages that triggers scale-out / the CloudWatch alarm."
}

# --- Video ASG (designed, not deployed by default) ---

variable "deploy_video_asg" {
  type        = bool
  default     = false
  description = "Set true only in an account where a full VPC + private subnets + AMI pipeline exists. Defaults to false — see README."
}

variable "video_worker_ami_id" {
  type    = string
  default = ""
}

variable "video_asg_max_size" {
  type    = number
  default = 6
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "video_worker_security_group_id" {
  type    = string
  default = ""
}

variable "ec2_instance_profile_arn" {
  type    = string
  default = ""
}

variable "video_queue_url" {
  type    = string
  default = ""
}
