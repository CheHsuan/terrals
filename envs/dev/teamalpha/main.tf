locals {
  environment = "dev"
  owner       = "teamalpha"
}

module "app_service" {
  source = "../../../modules/app_service"

  environment                    = local.environment
  owner                          = local.owner
  dynamodb_user_table_seed_phone = var.dynamodb_user_table_seed_phone
  lambda_alias_version           = var.lambda_alias_version
}
