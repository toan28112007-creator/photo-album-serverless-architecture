# API module: Cognito user pool + API Gateway HTTP API.
# Mirrors Section II-B2 / III-C of the design report. Cognito is not a hop
# in the request path — API Gateway validates the JWT against it before
# any Lambda invocation.

resource "aws_cognito_user_pool" "users" {
  name = "${var.project_name}-users-${var.environment}"

  password_policy {
    minimum_length    = 10
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-app-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.users.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.oauth_callback_urls
}

# Default Cognito-hosted domain — not a custom domain, deliberately, since
# this project doesn't provision a real Route 53 zone. See README.
resource "aws_cognito_user_pool_domain" "hosted_ui" {
  domain       = "${var.project_name}-${var.environment}-${var.suffix}"
  user_pool_id = aws_cognito_user_pool.users.id
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app_client.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
  }
}

resource "aws_apigatewayv2_integration" "app_api" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.app_api_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "app_routes" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.app_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.app_api_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
