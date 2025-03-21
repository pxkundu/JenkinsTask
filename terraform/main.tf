# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
}

# Lambda module
module "lambda" {
  source           = "./modules/lambda"
  function_name    = var.lambda_function_name
  lambda_zip_path  = "${path.module}/lambda-ec2.zip"  # ZIP in terraform/ directory
  source_code_hash = filebase64sha256("${path.module}/lambda-ec2.zip")
}

# API Gateway module
module "api_gateway" {
  source         = "./modules/api_gateway"
  api_name       = var.api_name
  lambda_arn     = module.lambda.lambda_arn
  lambda_name    = module.lambda.lambda_name
}
