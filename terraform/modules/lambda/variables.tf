variable "function_name" {
  type        = string
  description = "Name of the Lambda function"
}

variable "lambda_zip_path" {
  type        = string
  description = "Path to the Lambda ZIP file"
}

variable "source_code_hash" {
  type        = string
  description = "Hash of the Lambda source code"
}
