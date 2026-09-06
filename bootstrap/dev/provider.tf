provider "aws" {
  region = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://s3.localhost.localstack.cloud:4566" # Recommended domain-style for S3
    dynamodb = "http://localhost:4566"
  }
}
