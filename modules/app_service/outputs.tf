output "base_url" {
  description = "Base URL for API Gateway stage."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "local_invoke_url" {
  description = "Base URL for calling the API through LocalStack (base_url only resolves against real AWS)."
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.this.id}/${aws_api_gateway_stage.this.stage_name}/_user_request_"
}

output "s3_artifacts_id" {
  value = aws_s3_bucket.lambda_artifacts.id
}

output "s3_artifacts_arn" {
  value = aws_s3_bucket.lambda_artifacts.arn
}

output "dynamodb_user_table_name" {
  value = aws_dynamodb_table.user_table.name
}

output "dynamodb_user_table_arn" {
  value = aws_dynamodb_table.user_table.arn
}
