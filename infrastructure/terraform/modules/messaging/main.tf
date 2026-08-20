# Messaging module: SNS fan-out into per-type SQS queues, each with a DLQ.
# Mirrors Section II-B4 of the design report — this is the core decoupling
# mechanism: a backlog or failure in one media type never affects the other.

resource "aws_sns_topic" "upload_events" {
  name = "${var.project_name}-upload-events-${var.environment}"
}

# --- Dead-letter queues (one per pipeline) ---

resource "aws_sqs_queue" "image_dlq" {
  name                      = "${var.project_name}-image-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "video_dlq" {
  name                      = "${var.project_name}-video-dlq-${var.environment}"
  message_retention_seconds = 1209600
}

# --- Primary queues ---

resource "aws_sqs_queue" "image_queue" {
  name                       = "${var.project_name}-image-queue-${var.environment}"
  visibility_timeout_seconds = 60 # should exceed the image Lambda's max duration

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.image_dlq.arn
    maxReceiveCount      = 5
  })
}

resource "aws_sqs_queue" "video_queue" {
  name                       = "${var.project_name}-video-queue-${var.environment}"
  visibility_timeout_seconds = 900 # generous headroom for a transcoding job

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_dlq.arn
    maxReceiveCount      = 3
  })
}

# --- SNS -> SQS subscriptions, filtered by content type ---
# S3 event notifications carry the object key; the filter policy below
# matches on a message attribute set by the S3->SNS integration convention
# (content-type prefix). Adjust the filter to your actual key/tagging
# convention if you change the upload path.

resource "aws_sns_topic_subscription" "image_queue_sub" {
  topic_arn = aws_sns_topic.upload_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.image_queue.arn

  filter_policy = jsonencode({
    media_type = ["image"]
  })
}

resource "aws_sns_topic_subscription" "video_queue_sub" {
  topic_arn = aws_sns_topic.upload_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.video_queue.arn

  filter_policy = jsonencode({
    media_type = ["video"]
  })
}

# --- Permissions: allow SNS to publish into each queue ---

data "aws_iam_policy_document" "sqs_from_sns" {
  for_each = {
    image = aws_sqs_queue.image_queue.arn
    video = aws_sqs_queue.video_queue.arn
  }

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [each.value]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.upload_events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "image_queue_policy" {
  queue_url = aws_sqs_queue.image_queue.id
  policy    = data.aws_iam_policy_document.sqs_from_sns["image"].json
}

resource "aws_sqs_queue_policy" "video_queue_policy" {
  queue_url = aws_sqs_queue.video_queue.id
  policy    = data.aws_iam_policy_document.sqs_from_sns["video"].json
}

# --- Permission: allow S3 to publish into the SNS topic ---

data "aws_iam_policy_document" "sns_from_s3" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.upload_events.arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.raw_media_bucket_arn]
    }
  }
}

resource "aws_sns_topic_policy" "upload_events_policy" {
  arn    = aws_sns_topic.upload_events.arn
  policy = data.aws_iam_policy_document.sns_from_s3.json
}
