output "api_url_base" {
  description = "Base URL of the API Gateway stage"
  value       = module.api_gateway.api_invoke_url
}

output "api_url_instances" {
  description = "URL for fetching EC2 instances"
  value       = "${module.api_gateway.api_invoke_url}/instances"
}

output "api_url_start" {
  description = "URL for starting EC2 instances"
  value       = "${module.api_gateway.api_invoke_url}/start"
}

output "api_url_stop" {
  description = "URL for stopping EC2 instances"
  value       = "${module.api_gateway.api_invoke_url}/stop"
}
