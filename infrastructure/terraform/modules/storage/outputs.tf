output "raw_media_bucket_name" {
  value = aws_s3_bucket.raw_media.bucket
}

output "raw_media_bucket_arn" {
  value = aws_s3_bucket.raw_media.arn
}

output "derivatives_bucket_name" {
  value = aws_s3_bucket.derivatives.bucket
}

output "derivatives_bucket_arn" {
  value = aws_s3_bucket.derivatives.arn
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}
