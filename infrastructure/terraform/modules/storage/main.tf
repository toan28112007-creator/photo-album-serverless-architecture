# Storage module: raw media, derivatives, and frontend buckets.
# Mirrors Section II-B3 of the design report.

resource "aws_s3_bucket" "raw_media" {
  bucket = "${var.project_name}-raw-media-${var.environment}-${var.suffix}"
}

resource "aws_s3_bucket" "derivatives" {
  bucket = "${var.project_name}-derivatives-${var.environment}-${var.suffix}"
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${var.environment}-${var.suffix}"
}

# Raw and derivatives buckets are never public — CloudFront (with Origin
# Access Control) is the only intended path to their contents. See
# docs/design-decisions.md ADR-5.
resource "aws_s3_bucket_public_access_block" "raw_media" {
  bucket                  = aws_s3_bucket.raw_media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "derivatives" {
  bucket                  = aws_s3_bucket.derivatives.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Raw media is the trigger source for the whole processing pipeline: every
# ObjectCreated event is published to the SNS topic that fans out into the
# image/video SQS queues (see modules/messaging).
resource "aws_s3_bucket_notification" "raw_media_events" {
  bucket = aws_s3_bucket.raw_media.id

  topic {
    topic_arn = var.upload_topic_arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [var.topic_policy_dependency]
}

# Lifecycle: raw originals older than 90 days move to Infrequent Access,
# then Glacier at 180 days — reduces storage cost for content users rarely
# re-view. Referenced under Sustainability in the report (Section IV-F).
resource "aws_s3_bucket_lifecycle_configuration" "raw_media" {
  bucket = aws_s3_bucket.raw_media.id

  rule {
    id     = "raw-media-tiering"
    status = "Enabled"
    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_media" {
  bucket = aws_s3_bucket.raw_media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "derivatives" {
  bucket = aws_s3_bucket.derivatives.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
