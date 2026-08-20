output "image_processor_function_name" {
  value = aws_lambda_function.image_processor.function_name
}

output "app_api_function_name" {
  value = aws_lambda_function.app_api.function_name
}

output "app_api_invoke_arn" {
  value = aws_lambda_function.app_api.invoke_arn
}
