output "api_invoke_url" {
  value = aws_api_gateway_stage.this.invoke_url  # Base stage URL
}
