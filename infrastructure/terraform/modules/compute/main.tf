# Compute module.
#
# Lambda resources here (`image-processor`) are deployed as part of the MVP.
# The EC2 Auto Scaling Group at the bottom of this file is written and
# `terraform validate`-clean but gated behind `deploy_video_asg`, which
# defaults to false — see README "What's deployed vs. designed" and
# docs/design-decisions.md ADR-1 for why it isn't applied in the Learner
# Lab environment this was built against.

# --- Image processing Lambda ---

resource "aws_lambda_function" "image_processor" {
  function_name = "${var.project_name}-image-processor-${var.environment}"
  role          = var.lambda_role_arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"
  timeout       = 30
  memory_size   = 256

  filename         = var.image_processor_zip_path
  source_code_hash = filebase64sha256(var.image_processor_zip_path)

  environment {
    variables = {
      DERIVATIVES_BUCKET = var.derivatives_bucket_name
      METADATA_TABLE     = var.metadata_table_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "image_queue_trigger" {
  event_source_arn = var.image_queue_arn
  function_name    = aws_lambda_function.image_processor.arn
  batch_size       = 5
}

# --- App API Lambda (business logic + pre-signed URL issuance) ---

resource "aws_lambda_function" "app_api" {
  function_name = "${var.project_name}-app-api-${var.environment}"
  role          = var.lambda_role_arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"
  timeout       = 15
  memory_size   = 128

  filename         = var.app_api_zip_path
  source_code_hash = filebase64sha256(var.app_api_zip_path)

  environment {
    variables = {
      RAW_MEDIA_BUCKET  = var.raw_media_bucket_name
      METADATA_TABLE    = var.metadata_table_name
      MAX_VIDEO_SECONDS = "300" # 5-minute cap, see docs/cost-model.md
    }
  }
}

# --- CloudWatch alarm on video queue depth ---
# Referenced in the report as the metric driving EC2 ASG scaling
# (queue depth, not CPU) — deployed even though the ASG itself isn't, so
# the monitoring approach can be demonstrated against a real queue.

resource "aws_cloudwatch_metric_alarm" "video_queue_backlog" {
  alarm_name          = "${var.project_name}-video-queue-backlog-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.video_queue_backlog_threshold

  dimensions = {
    QueueName = var.video_queue_name
  }

  alarm_description = "Video queue backlog exceeds threshold; in a deployed EC2 ASG this would drive scale-out (see ADR-1)."
}

# ---------------------------------------------------------------------
# DESIGNED, NOT DEPLOYED: EC2 Auto Scaling Group for video transcoding.
# Gated behind deploy_video_asg (default false). See ADR-1.
# ---------------------------------------------------------------------

resource "aws_launch_template" "video_worker" {
  count         = var.deploy_video_asg ? 1 : 0
  name_prefix   = "${var.project_name}-video-worker-"
  image_id      = var.video_worker_ami_id
  instance_type = "t3.medium" # see ADR-1 / README for the c5.xlarge revision note

  iam_instance_profile {
    arn = var.ec2_instance_profile_arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.video_worker_security_group_id]
  }

  user_data = base64encode(templatefile("${path.module}/templates/video-worker-userdata.sh.tpl", {
    video_queue_url    = var.video_queue_url
    derivatives_bucket = var.derivatives_bucket_name
    metadata_table     = var.metadata_table_name
    max_video_seconds  = 300
  }))
}

resource "aws_autoscaling_group" "video_worker" {
  count               = var.deploy_video_asg ? 1 : 0
  name                = "${var.project_name}-video-worker-asg-${var.environment}"
  min_size            = 2
  max_size            = var.video_asg_max_size
  desired_capacity    = 2
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.video_worker[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-video-worker"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "video_worker_target_tracking" {
  count                  = var.deploy_video_asg ? 1 : 0
  name                   = "${var.project_name}-video-worker-queue-depth"
  autoscaling_group_name = aws_autoscaling_group.video_worker[0].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.video_queue_backlog_threshold

    customized_metric_specification {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      statistic   = "Average"

      metric_dimension {
        name  = "QueueName"
        value = var.video_queue_name
      }
    }
  }
}
