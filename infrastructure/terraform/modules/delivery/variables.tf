variable "project_name" {
  type    = string
  default = "photoalbum"
}

variable "environment" {
  type = string
}

variable "frontend_bucket_name" {
  type = string
}

variable "frontend_bucket_arn" {
  type = string
}

variable "frontend_bucket_regional_domain_name" {
  type = string
}

variable "derivatives_bucket_name" {
  type = string
}

variable "derivatives_bucket_arn" {
  type = string
}

variable "derivatives_bucket_regional_domain_name" {
  type = string
}

variable "web_acl_arn" {
  type        = string
  default     = null
  description = "Optional AWS WAF Web ACL ARN. Null deploys CloudFront without WAF attached."
}
