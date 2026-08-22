# Terraform Bootstrap

Creates the S3 bucket (versioned, encrypted, private) used as the
**remote backend** for the main stack in `../terraform`. Locking uses
Terraform's native S3 lock file feature (`use_lockfile = true`,
Terraform ≥ 1.10) — no separate DynamoDB table required.

Run this **once**, before the first `terraform init` of the main stack.
It has its own local state — do not try to merge it into the main stack's
state, and do not run it again unless you're intentionally recreating the
backend.

## Usage

```bash
cd infrastructure/terraform-bootstrap
terraform init
terraform apply
```

After `apply`, copy the printed `backend_config_snippet` output value and
paste it into `../terraform/backend.tf`, replacing the commented-out
placeholder block. Then:

```bash
cd ../terraform
terraform init -migrate-state
```

`-migrate-state` moves any existing local state into S3 without losing
anything already tracked; confirm with `yes` when prompted.

## Why this is separate from the main stack

Terraform can't use an S3 bucket as its own backend before that bucket
exists — there's no way for the main stack to create its own remote
storage and immediately start using it in the same `apply`. This
bootstrap stack breaks that circular dependency: it stays on local state
(it's small and rarely changes), while the main stack's state moves to S3
once the backend exists.

## Cost

Negligible at this scale: S3 versioned storage for a few KB of state
files. Falls well within AWS Always Free tier limits.
