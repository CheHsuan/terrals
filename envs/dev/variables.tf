variable "lambda_artifacts_name" {
  type    = string
  default = "terrals-lambda-artifacts"
}

variable "dynamodb_user_name" {
  type    = string
  default = "User"
}

variable "dynamodb_user_billing_mode" {
  type    = string
  default = "PROVISIONED"
}

variable "dynamodb_user_read_capacity" {
  type    = number
  default = 10
}

variable "dynamodb_user_write_capacity" {
  type    = number
  default = 10
}

variable "dynamodb_user_seed_phone" {
  description = "initial user phone(PII)"
  type        = string
  sensitive   = true
}
