output "cloudfront_domain" {
  value = module.delivery.distribution_domain_name
}

output "api_endpoint" {
  value = module.api.api_endpoint
}

output "cognito_hosted_ui_domain" {
  value = module.api.hosted_ui_domain
}

output "raw_media_bucket" {
  value = module.storage.raw_media_bucket_name
}

output "metadata_table" {
  value = aws_dynamodb_table.metadata.name
}
