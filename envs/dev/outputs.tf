output "s3_artifacts_id" {
  value = aws_s3_bucket.terrals_lambda_artifacts.id
}

output "s3_artifacts_arn" {
  value = aws_s3_bucket.terrals_lambda_artifacts.arn
}

output "dynamodb_user_name" {
  value = aws_dynamodb_table.terrals_dynamodb_user.name
}

output "dynamodb_user_arn" {
  value = aws_dynamodb_table.terrals_dynamodb_user.arn
}
