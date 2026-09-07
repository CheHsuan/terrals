variable "environment" {
  type = string
}

variable "owner" {
  type = string
}

variable "lambda_alias_version" {
  type    = string
  default = null
}

variable "dynamodb_user_table_billing_mode" {
  type    = string
  default = "PROVISIONED"
}

variable "dynamodb_user_table_read_capacity" {
  type    = number
  default = 10
}

variable "dynamodb_user_table_write_capacity" {
  type    = number
  default = 10
}

variable "dynamodb_user_table_seed_phone" {
  description = "initial user phone(PII)"
  type        = string
  sensitive   = true
}
