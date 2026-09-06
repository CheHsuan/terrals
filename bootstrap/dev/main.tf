locals {
  project                  = "terrals"
  environment              = "dev"
  name_prefix              = local.project
  terraform_artifacts_name = "${local.name_prefix}-terraform-state-artifacts"
  dynamodb_lock_table_name = "${local.name_prefix}-terraform-state-lock"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    Owner       = local.project
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "terraform_state_artifacts" {
  bucket = local.terraform_artifacts_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "terraform_state_artifacts" {
  bucket                  = aws_s3_bucket.terraform_state_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_artifacts_conf" {
  bucket = aws_s3_bucket.terraform_state_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_state_lock_table" {
  name         = local.dynamodb_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.common_tags
}
