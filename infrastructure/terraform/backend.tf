# Remote state backend.
#
# This file is intentionally checked into version control WITHOUT real
# values filled in — bucket names are account-specific and the backend
# block cannot use variables (Terraform limitation: backend config is
# read before any variables are resolved).
#
# Setup:
#   1. Run infrastructure/terraform-bootstrap once (see its README) to
#      create the S3 state bucket.
#   2. Copy the `backend_config_snippet` output value and paste it here,
#      replacing the placeholder block below.
#   3. Run `terraform init -migrate-state` in this directory to migrate
#      any existing local state into the new backend.
#
# Until step 2 is done, Terraform uses local state (terraform.tfstate in
# this directory) exactly as before — this file has no effect unmodified,
# since the backend block below is commented out.

# terraform {
#   backend "s3" {
#     bucket       = "photoalbum-tfstate-XXXXXX"   # from bootstrap output
#     key          = "photoalbum/dev/terraform.tfstate"
#     region       = "ap-southeast-2"
#     use_lockfile = true   # native S3 locking (Terraform >= 1.10) — no DynamoDB table needed
#     encrypt      = true
#   }
# }
