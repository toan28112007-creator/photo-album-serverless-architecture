variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "photoalbum"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment name."
}

variable "use_lab_role" {
  type        = bool
  default     = false
  description = "Set true on an AWS Academy Learner Lab account, which cannot create custom IAM roles. Attaches the pre-existing LabRole to all Lambda functions instead."
}

variable "lab_role_arn" {
  type        = string
  default     = ""
  description = "ARN of the pre-existing LabRole, e.g. arn:aws:iam::<account-id>:role/LabRole. Required when use_lab_role = true."
}

variable "deploy_video_asg" {
  type        = bool
  default     = false
  description = "See modules/compute/variables.tf — false by default; this repo does not deploy the EC2 video pipeline. See README."
}
