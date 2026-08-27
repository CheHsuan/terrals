resource "aws_s3_bucket" "terrals-lambda-artifacts" {
  bucket = "terrals-lambda-artifacts"
}

resource "aws_s3_bucket_public_access_block" "terrals-lambda-artifacts" {
  bucket                  = aws_s3_bucket.terrals-lambda-artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
