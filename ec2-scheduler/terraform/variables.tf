variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Partha Lambda function"
  default     = "partha-ec2-scheduler-lambda"
}

variable "api_gateway_name" {
  description = "Partha API Gateway"
  default     = "partha-ec2-scheduler-api"
}
