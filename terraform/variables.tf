variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "ParthaEc2ListFunction"
}

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
  default     = "ParthaEC2ListAPI"
}
