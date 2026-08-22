# Bootstrap stack — creates the S3 bucket and DynamoDB table used as the
# remote backend for the main stack in ../terraform.
#
# This is deliberately a SEPARATE, tiny Terraform config with its own
# local state. It must be applied once, manually, before the main stack
# can use a remote backend — Terraform can't use a bucket as its own
# backend before that bucket exists.
#
# Usage:
#   cd infrastructure/terraform-bootstrap
#   terraform init
#   terraform apply
#   (note the two output values, then go configure ../terraform/backend.tf)

# Bootstrap stack — creates the S3 bucket used as the remote backend for
# the main stack in ../terraform. Locking uses Terraform's native S3 lock
# file (requires Terraform >= 1.10), so no separate DynamoDB table is
# needed.
#
# This is deliberately a SEPARATE, tiny Terraform config with its own
# local state. It must be applied once, manually, before the main stack
# can use a remote backend — Terraform can't use a bucket as its own
# backend before that bucket exists.
#
# Usage:
#   cd infrastructure/terraform-bootstrap
#   terraform init
#   terraform apply
#   (note the output value, then go configure ../terraform/backend.tf)

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "photoalbum"
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tfstate-${random_id.suffix.hex}"

  # Prevents `terraform destroy` (run against the wrong directory, by
  # accident) from deleting the bucket that holds every other stack's
  # history.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled" # every state write becomes a recoverable version
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "backend_config_snippet" {
  description = "Paste this into infrastructure/terraform/backend.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tf_state.bucket}"
        key          = "photoalbum/dev/terraform.tfstate"
        region       = "${var.aws_region}"
        use_lockfile = true
        encrypt      = true
      }
    }
  EOT
}
