# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "partha-ec2-scheduler-lambda-role-${var.deployment_id}"

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

# IAM Policy for Lambda (EC2 permissions and CloudWatch Logs)
resource "aws_iam_policy" "lambda_policy" {
  name        = "partha-ec2-scheduler-lambda-policy-${var.deployment_id}"
  description = "Policy for Lambda to manage EC2 instances and write logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "ec2_scheduler_lambda" {
  filename         = "../lambda_function.zip"
  function_name    = "${var.lambda_function_name}-${var.deployment_id}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 60
  memory_size      = 128

  source_code_hash = filebase64sha256("../lambda_function.zip")
}

# API Gateway
resource "aws_api_gateway_rest_api" "ec2_scheduler_api" {
  name        = "${var.api_gateway_name}-${var.deployment_id}"
  description = "API Gateway for EC2 Scheduler"
}

# Resource for /ec2 path
resource "aws_api_gateway_resource" "ec2_resource" {
  rest_api_id = aws_api_gateway_rest_api.ec2_scheduler_api.id
  parent_id   = aws_api_gateway_rest_api.ec2_scheduler_api.root_resource_id
  path_part   = "ec2"
}

# POST Method for /ec2
resource "aws_api_gateway_method" "ec2_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ec2_scheduler_api.id
  resource_id   = aws_api_gateway_resource.ec2_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integration with Lambda
resource "aws_api_gateway_integration" "ec2_lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.ec2_scheduler_api.id
  resource_id             = aws_api_gateway_resource.ec2_resource.id
  http_method             = aws_api_gateway_method.ec2_post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ec2_scheduler_lambda.invoke_arn
}

# Lambda Permission to allow API Gateway to invoke it
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ec2_scheduler_api.execution_arn}/*/*"
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "ec2_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.ec2_lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.ec2_scheduler_api.id
  stage_name  = "prod"
}
