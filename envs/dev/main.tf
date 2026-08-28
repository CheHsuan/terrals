locals {
  project     = "terrals"
  environment = "dev"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    Owner       = "terrals"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "terrals_lambda_artifacts" {
  bucket = var.lambda_artifacts_name

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "terrals_lambda_artifacts" {
  bucket                  = aws_s3_bucket.terrals_lambda_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terrals_dynamodb_user" {
  name           = var.dynamodb_user_name
  billing_mode   = var.dynamodb_user_billing_mode
  read_capacity  = var.dynamodb_user_read_capacity
  write_capacity = var.dynamodb_user_write_capacity
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table_item" "terrals_dynamodb_user_seed" {
  table_name = aws_dynamodb_table.terrals_dynamodb_user.name
  hash_key   = aws_dynamodb_table.terrals_dynamodb_user.hash_key

  item = jsonencode({
    Id    = { S = "123e4567-e89b-12d3-a456-426614174000" }
    Name  = { S = "Seed User" }
    Phone = { S = var.dynamodb_user_seed_phone }
  })
}
