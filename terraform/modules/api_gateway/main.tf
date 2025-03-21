resource "aws_api_gateway_rest_api" "this" {
  name = var.api_name
}

# Resource for /instances (GET)
resource "aws_api_gateway_resource" "instances" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "instances"
}

resource "aws_api_gateway_method" "instances_get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.instances.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "instances_get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.instances.id
  http_method             = aws_api_gateway_method.instances_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn
}

# Resource for /start (POST)
resource "aws_api_gateway_resource" "start" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "start"
}

resource "aws_api_gateway_method" "start_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.start.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "start_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.start.id
  http_method             = aws_api_gateway_method.start_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn
}

# Resource for /stop (POST)
resource "aws_api_gateway_resource" "stop" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "stop"
}

resource "aws_api_gateway_method" "stop_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.stop.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "stop_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.stop.id
  http_method             = aws_api_gateway_method.stop_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn
}

# Resource for /tag (POST) - New
resource "aws_api_gateway_resource" "tag" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "tag"
}

resource "aws_api_gateway_method" "tag_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.tag.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tag_post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.tag.id
  http_method             = aws_api_gateway_method.tag_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_arn
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  depends_on  = [
    aws_api_gateway_integration.instances_get,
    aws_api_gateway_integration.start_post,
    aws_api_gateway_integration.stop_post,
    aws_api_gateway_integration.tag_post  # Added dependency for /tag
  ]
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.instances.id,
      aws_api_gateway_method.instances_get.id,
      aws_api_gateway_integration.instances_get.id,
      aws_api_gateway_resource.start.id,
      aws_api_gateway_method.start_post.id,
      aws_api_gateway_integration.start_post.id,
      aws_api_gateway_resource.stop.id,
      aws_api_gateway_method.stop_post.id,
      aws_api_gateway_integration.stop_post.id,
      aws_api_gateway_resource.tag.id,           # Added for /tag
      aws_api_gateway_method.tag_post.id,        # Added for /tag
      aws_api_gateway_integration.tag_post.id    # Added for /tag
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
  # Removed depends_on to break the cycle; deployment_id already ensures order
}
