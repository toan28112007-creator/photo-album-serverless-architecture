resource "random_id" "suffix" {
  byte_length = 3
}

# --- DynamoDB: metadata table, on-demand capacity (ADR-2) ---

resource "aws_dynamodb_table" "metadata" {
  name         = "${var.project_name}-metadata-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # on-demand — no capacity planning, see ADR-2
  hash_key     = "media_id"

  attribute {
    name = "media_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# --- IAM: custom least-privilege role, OR the Learner Lab's pre-existing
# LabRole, selected via var.use_lab_role. See README "Deploying this
# yourself" and docs/design-decisions.md.

data "aws_iam_policy_document" "lambda_assume" {
  count = var.use_lab_role ? 0 : 1

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  count              = var.use_lab_role ? 0 : 1
  name               = "${var.project_name}-lambda-exec-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count      = var.use_lab_role ? 0 : 1
  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped-down policy: read the raw bucket, write the derivatives bucket
# and the metadata table, consume from the queues. Deliberately does NOT
# grant delete on raw media or any cross-bucket write, per the
# least-privilege principle in Section II-B6 of the report.
data "aws_iam_policy_document" "lambda_permissions" {
  count = var.use_lab_role ? 0 : 1

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.raw_media_bucket_arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.storage.derivatives_bucket_arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [aws_dynamodb_table.metadata.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      module.messaging.image_queue_arn,
      module.messaging.video_queue_arn,
    ]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  count  = var.use_lab_role ? 0 : 1
  name   = "${var.project_name}-lambda-permissions-${var.environment}"
  role   = aws_iam_role.lambda_execution[0].id
  policy = data.aws_iam_policy_document.lambda_permissions[0].json
}

locals {
  lambda_role_arn = var.use_lab_role ? var.lab_role_arn : aws_iam_role.lambda_execution[0].arn
}

# --- Modules ---

module "messaging" {
  source = "./modules/messaging"

  project_name         = var.project_name
  environment          = var.environment
  raw_media_bucket_arn = module.storage.raw_media_bucket_arn
}

module "storage" {
  source = "./modules/storage"

  project_name            = var.project_name
  environment             = var.environment
  suffix                  = random_id.suffix.hex
  upload_topic_arn        = module.messaging.topic_arn
  topic_policy_dependency = module.messaging.topic_policy
}

module "compute" {
  source = "./modules/compute"

  project_name            = var.project_name
  environment             = var.environment
  lambda_role_arn         = local.lambda_role_arn
  image_queue_arn         = module.messaging.image_queue_arn
  raw_media_bucket_name   = module.storage.raw_media_bucket_name
  derivatives_bucket_name = module.storage.derivatives_bucket_name
  metadata_table_name     = aws_dynamodb_table.metadata.name
  video_queue_name        = module.messaging.video_queue_url
  deploy_video_asg        = var.deploy_video_asg
}

module "api" {
  source = "./modules/api"

  project_name          = var.project_name
  environment           = var.environment
  suffix                = random_id.suffix.hex
  aws_region            = var.aws_region
  app_api_invoke_arn    = module.compute.app_api_invoke_arn
  app_api_function_name = module.compute.app_api_function_name
}

module "delivery" {
  source = "./modules/delivery"

  project_name                            = var.project_name
  environment                             = var.environment
  frontend_bucket_name                    = module.storage.frontend_bucket_name
  frontend_bucket_arn                     = "arn:aws:s3:::${module.storage.frontend_bucket_name}"
  frontend_bucket_regional_domain_name    = "${module.storage.frontend_bucket_name}.s3.${var.aws_region}.amazonaws.com"
  derivatives_bucket_name                 = module.storage.derivatives_bucket_name
  derivatives_bucket_arn                  = module.storage.derivatives_bucket_arn
  derivatives_bucket_regional_domain_name = "${module.storage.derivatives_bucket_name}.s3.${var.aws_region}.amazonaws.com"
}