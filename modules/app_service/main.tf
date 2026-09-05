locals {
  project                  = "terrals"
  name_prefix              = "${var.owner}-${local.project}"
  lambda_function_name     = "${local.name_prefix}-hello-world"
  lambda_artifacts_name    = "${local.name_prefix}-lambda-artifacts"
  lambda_iam_role_name     = "${local.lambda_function_name}-role"
  dynamodb_user_table_name = "${local.name_prefix}-user"
  api_gw_rest_api_name     = "${local.name_prefix}-serverless-lambda-gw"
  seed_user_id             = "123e4567-e89b-12d3-a456-426614174000"


  common_tags = {
    Project     = local.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role" "lambda_iam_role" {
  name = local.lambda_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb_read" {
  name = "${local.lambda_function_name}-dynamodb-read"
  role = aws_iam_role.lambda_iam_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.user_table.arn
      }
    ]
  })
}

resource "aws_lambda_function" "hello_world" {
  function_name = local.lambda_function_name

  s3_bucket = aws_s3_bucket.lambda_artifacts.id
  s3_key    = aws_s3_object.hello_world.key

  runtime = "nodejs20.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.hello_world.output_base64sha256

  role = aws_iam_role.lambda_iam_role.arn

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.user_table.name
      SEED_USER_ID = local.seed_user_id
    }
  }
}

data "archive_file" "hello_world" {
  type = "zip"

  source_dir  = "${path.module}/hello-world"
  output_path = "${path.module}/hello-world.zip"
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = local.lambda_artifacts_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket                  = aws_s3_bucket.lambda_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "hello_world" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  key    = "hello-world.zip"
  source = data.archive_file.hello_world.output_path

  etag = filemd5(data.archive_file.hello_world.output_path)
}

resource "aws_dynamodb_table" "user_table" {
  name           = local.dynamodb_user_table_name
  billing_mode   = var.dynamodb_user_table_billing_mode
  read_capacity  = var.dynamodb_user_table_read_capacity
  write_capacity = var.dynamodb_user_table_write_capacity
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table_item" "user_seed" {
  table_name = aws_dynamodb_table.user_table.name
  hash_key   = aws_dynamodb_table.user_table.hash_key

  item = jsonencode({
    Id    = { S = local.seed_user_id }
    Name  = { S = "Seed User" }
    Phone = { S = var.dynamodb_user_table_seed_phone }
  })
}

resource "aws_api_gateway_rest_api" "this" {
  name = local.api_gw_rest_api_name
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "hello_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello_world.invoke_arn
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.hello_get.id,
      aws_api_gateway_integration.hello.uri,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "serverless_lambda_stage"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
