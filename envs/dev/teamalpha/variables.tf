variable "dynamodb_user_table_seed_phone" {
  description = "initial user phone(PII)"
  type        = string
  sensitive   = true
}

variable "lambda_alias_version" {
  description = "Pin the live alias to a specific published version for rollback; null follows the latest version"
  type        = string
  default     = null
}
