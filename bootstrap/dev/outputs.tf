output "bucket_name" {
  value = aws_s3_bucket.terraform_state_artifacts.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_state_lock_table.name
}

