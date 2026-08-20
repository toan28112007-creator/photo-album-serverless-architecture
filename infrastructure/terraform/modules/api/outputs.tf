output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.app_client.id
}

output "hosted_ui_domain" {
  value = aws_cognito_user_pool_domain.hosted_ui.domain
}
