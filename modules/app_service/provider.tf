#Define provider
provider "aws" {
  region = "us-east-1"

  # Crucial flags to prevent Terraform from attempting live AWS validation
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Global endpoint routing
  endpoints {
    s3         = "http://s3.localhost.localstack.cloud:4566" # Recommended domain-style for S3
    dynamodb   = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    apigateway = "http://localhost:4566"
  }
}
