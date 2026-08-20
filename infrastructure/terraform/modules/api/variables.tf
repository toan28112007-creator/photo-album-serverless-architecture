variable "project_name" {
  type    = string
  default = "photoalbum"
}

variable "environment" {
  type = string
}

variable "suffix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "app_api_invoke_arn" {
  type = string
}

variable "app_api_function_name" {
  type = string
}

variable "oauth_callback_urls" {
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
  description = "Update with the real frontend URL once deployed behind CloudFront."
}
