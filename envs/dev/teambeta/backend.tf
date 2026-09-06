terraform {
  backend "s3" {
    bucket         = "terrals-terraform-state-artifacts"
    key            = "teambeta/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terrals-terraform-state-lock"

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true

    endpoints = {
      s3       = "http://s3.localhost.localstack.cloud:4566"
      dynamodb = "http://localhost:4566"
    }
  }
}
