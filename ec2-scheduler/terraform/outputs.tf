output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_deployment.ec2_api_deployment.invoke_url}/ec2"
}
