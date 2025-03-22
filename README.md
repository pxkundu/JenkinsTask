# Method of Procedure (MOP) for Automate EC2 START & STOP by using Lambda, Google Sheet, App Script, API Gateway
By: Partha Sarathi Kundu
Date: 03/21/2025

This document provides a comprehensive guide to the EC2 Scheduler project, which automates the management of EC2 instances (start, stop, and tagging) using AWS services, Terraform, Google Sheets, and Google Apps Script. The project includes notifications via email, Google Chat, and Slack for operations like starting, stopping, tagging, and shift updates. It also features cost analysis for API Gateway usage. Below, we’ll cover the setup, installation, configurations, project structure, code files, Google Sheets integration, cost analysis, notification systems, and best practices.

---

## 1. Project Overview

The EC2 Scheduler project automates the management of EC2 instances by:
- Allowing users to start, stop, and tag EC2 instances via a Google Sheet interface.
- Scheduling instances to start or stop based on predefined shifts.
- Tagging instances with a `Shift` tag to indicate their operational schedule.
- Sending notifications for operations (`start`, `stop`, `tag update`, `shift update`) via email, Google Chat, and Slack.
- Estimating and updating API Gateway cost analysis in the Google Sheet.

### Key Components
- **AWS Infrastructure**:
  - API Gateway: Exposes endpoints (`/instances`, `/start`, `/stop`, `/tag`) to interact with EC2 instances.
  - Lambda Function: Handles the logic for listing, starting, stopping, and tagging EC2 instances.
  - IAM Roles: Grants necessary permissions to the Lambda function.
- **Terraform**: Manages the AWS infrastructure as code.
- **Google Sheets**: Provides a user interface to manage EC2 instances.
- **Google Apps Script**: Integrates Google Sheets with the API Gateway, handles scheduling, and sends notifications.
- **Notifications**:
  - Email: Sent to a manager’s email address.
  - Google Chat: Sent to a chat space via a webhook.
  - Slack: Sent to a channel via a webhook.
- **Cost Analysis**: Tracks API Gateway usage costs in the Google Sheet.

---

## 2. Project Setup and Installation

### 2.1 Prerequisites
- **AWS Account**: With permissions to create API Gateway, Lambda, IAM roles, and EC2 instances.
- **Terraform**: Installed on your local machine (version 1.5.0 or later).
- **Python**: For the Lambda function (version 3.9).
- **Google Account**: For Google Sheets and Apps Script.
- **Slack Workspace**: For Slack notifications.
- **Google Chat Space**: For Google Chat notifications.
- **Git**: For version control.
- **Text Editor**: (e.g., VS Code) for editing code files.

### 2.2 Initial Setup
1. **Clone the Repository**:
   ```bash
   git clone <repository-url>
   cd aws-repo/JenkinsTask
   ```
   - Replace `<repository-url>` with your repository URL.

2. **Install Terraform**:
   - On Ubuntu:
     ```bash
     sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
     curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
     sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
     sudo apt-get update && sudo apt-get install terraform
     ```
   - Verify installation:
     ```bash
     terraform --version
     ```

3. **Set Up AWS Credentials**:
   - Configure your AWS CLI with your credentials:
     ```bash
     aws configure
     ```
     - Enter your AWS Access Key ID, Secret Access Key, region (e.g., `us-east-1`), and output format (e.g., `json`).

4. **Create a Google Sheet**:
   - Open Google Sheets and create a new spreadsheet named `EC2Scheduler`.
   - This sheet will be used to manage EC2 instances and display cost analysis.

5. **Set Up Google Chat Webhook**:
   - Open Google Chat, go to your space, and click **Apps & integrations > Add webhooks**.
   - Name the webhook (e.g., `EC2SchedulerBot`) and copy the webhook URL (e.g., `https://chat.googleapis.com/v1/spaces/XXXX/messages?key=YYYY&token=ZZZZ`).

6. **Set Up Slack Webhook**:
   - In your Slack workspace, go to **Apps > Manage Apps > Custom Integrations > Incoming WebHooks**.
   - Add a webhook, select a channel (e.g., `#ec2-notifications`), and copy the webhook URL (e.g., `https://hooks.slack.com/services/TXXXX/BXXXX/XXXX`).

---

## 3. Project Folder Structure

The project is organized as follows:

```
aws-repo/
└── JenkinsTask/
    ├── googleApps/
    │   ├── Code.gs          # Main Google Apps Script for EC2 operations and notifications
    │   ├── style.gs         # Styling functions for Google Sheets
    │   └── costAnalyzer.gs  # Cost analysis functions
    ├── lambda/
    │   └── main.py          # Lambda function to handle API Gateway requests
    ├── terraform/
    │   ├── main.tf          # Root Terraform file to call modules
    │   ├── outputs.tf       # Root-level outputs (e.g., API Gateway URLs)
    │   ├── variables.tf     # Variables for the root module
    │   ├── lambda-ec2.zip   # Zipped Lambda function code
    │   └── modules/
    │       ├── api_gateway/
    │       │   ├── main.tf      # API Gateway configuration
    │       │   ├── outputs.tf   # API Gateway outputs (e.g., endpoint URLs)
    │       │   └── variables.tf # API Gateway variables
    │       └── lambda/
    │           ├── main.tf      # Lambda function configuration
    │           ├── outputs.tf   # Lambda outputs (e.g., ARN, name)
    │           └── variables.tf # Lambda variables
```

### File Descriptions
- **googleApps/Code.gs**: Main script for interacting with API Gateway, managing shifts, sending notifications, and handling Google Sheet events.
- **googleApps/style.gs**: Contains functions to style the Google Sheets (`styleEC2SchedulerSheet`, `styleDefinedShiftsSheet`).
- **googleApps/costAnalyzer.gs**: Handles API Gateway cost estimation and updates the `CostAnalysis` sheet.
- **lambda/main.py**: Lambda function to handle API Gateway requests (`/instances`, `/start`, `/stop`, `/tag`).
- **terraform/main.tf**: Root Terraform file that calls the `api_gateway` and `lambda` modules.
- **terraform/outputs.tf**: Outputs the API Gateway endpoint URLs.
- **terraform/variables.tf**: Defines variables like `region`, `lambda_function_name`, and `api_name`.
- **terraform/modules/api_gateway/main.tf**: Configures the API Gateway with endpoints.
- **terraform/modules/api_gateway/outputs.tf**: Outputs the API Gateway endpoint URLs.
- **terraform/modules/api_gateway/variables.tf**: Defines variables for the API Gateway module.
- **terraform/modules/lambda/main.tf**: Configures the Lambda function and IAM role.
- **terraform/modules/lambda/outputs.tf**: Outputs the Lambda ARN and name.
- **terraform/modules/lambda/variables.tf**: Defines variables for the Lambda module.

---

## 4. Terraform Configuration and Deployment

### 4.1 Terraform Files

#### `terraform/variables.tf`
```hcl
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  default     = "ec2_scheduler_lambda"
}

variable "api_name" {
  description = "Name of the API Gateway"
  default     = "ec2_scheduler_api"
}
```

#### `terraform/main.tf`
```hcl
# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
}

# Lambda module
module "lambda" {
  source               = "./modules/lambda"
  function_name        = var.lambda_function_name
  lambda_zip_path      = "${path.module}/lambda-ec2.zip"
  source_code_hash     = filebase64sha256("${path.module}/lambda-ec2.zip")
  source_dir           = "../lambda"
  api_gateway_execution_arn = "${module.api_gateway.execution_arn}/*/*"
  region               = var.region
}

# API Gateway module
module "api_gateway" {
  source         = "./modules/api_gateway"
  api_name       = var.api_name
  lambda_arn     = module.lambda.lambda_invoke_arn
  lambda_name    = module.lambda.lambda_name
  stage_name     = "prod"
}
```

#### `terraform/outputs.tf`
```hcl
output "instances_url" {
  description = "URL for the /instances endpoint"
  value       = "${module.api_gateway.api_endpoint}/prod/instances"
}

output "start_url" {
  description = "URL for the /start endpoint"
  value       = "${module.api_gateway.api_endpoint}/prod/start"
}

output "stop_url" {
  description = "URL for the /stop endpoint"
  value       = "${module.api_gateway.api_endpoint}/prod/stop"
}

output "tag_url" {
  description = "URL for the /tag endpoint"
  value       = "${module.api_gateway.api_endpoint}/prod/tag"
}
```

#### `terraform/modules/api_gateway/main.tf`
```hcl
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

# Resource for /tag (POST)
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
    aws_api_gateway_integration.tag_post
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
      aws_api_gateway_resource.tag.id,
      aws_api_gateway_method.tag_post.id,
      aws_api_gateway_integration.tag_post.id
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
}
```

#### `terraform/modules/api_gateway/outputs.tf`
```hcl
output "api_endpoint" {
  description = "Base URL of the API Gateway"
  value       = aws_api_gateway_deployment.this.invoke_url
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.this.execution_arn
}
```

#### `terraform/modules/api_gateway/variables.tf`
```hcl
variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "lambda_arn" {
  description = "ARN of the Lambda function"
  type        = string
}

variable "lambda_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "stage_name" {
  description = "Stage name for the API Gateway deployment"
  type        = string
  default     = "prod"
}
```

#### `terraform/modules/lambda/main.tf`
```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:CreateTags",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  filename         = var.lambda_zip_path
  runtime          = "python3.9"
  handler          = "main.lambda_handler"
  role             = aws_iam_role.lambda_exec.arn
  source_code_hash = var.source_code_hash
  timeout          = 30
}
```

#### `terraform/modules/lambda/outputs.tf`
```hcl
output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.this.invoke_arn
}

output "lambda_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}
```

#### `terraform/modules/lambda/variables.tf`
```hcl
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_zip_path" {
  description = "Path to the Lambda function zip file"
  type        = string
}

variable "source_code_hash" {
  description = "Hash of the Lambda function source code"
  type        = string
}

variable "source_dir" {
  description = "Source directory for the Lambda function code"
  type        = string
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}
```

### 4.2 Deploy the Infrastructure
1. **Navigate to the Terraform Directory**:
   ```bash
   cd terraform
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Plan the Deployment**:
   ```bash
   terraform plan
   ```

4. **Apply the Changes**:
   ```bash
   terraform apply
   ```
   - Confirm with `yes`.

5. **Capture Outputs**:
   - After deployment, note the API Gateway URLs from the outputs:
     - `instances_url`
     - `start_url`
     - `stop_url`
     - `tag_url`

---

## 5. Lambda Function Configuration

### 5.1 `lambda/main.py`
The Lambda function handles requests from API Gateway and interacts with EC2.

```python
import json
import boto3
import os

# Initialize EC2 client
region = os.environ.get('REGION', 'us-east-1')
ec2_client = boto3.client('ec2', region_name=region)

def lambda_handler(event, context):
    try:
        # Parse the HTTP method and path
        http_method = event['httpMethod']
        path = event['path']

        if http_method == 'GET' and path == '/instances':
            return list_instances()
        elif http_method == 'POST' and path == '/start':
            return start_instances(event)
        elif http_method == 'POST' and path == '/stop':
            return stop_instances(event)
        elif http_method == 'POST' and path == '/tag':
            return tag_instances(event)
        else:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Not Found'})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def list_instances():
    response = ec2_client.describe_instances()
    instances = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            name = next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed')
            instances.append({
                'InstanceId': instance['InstanceId'],
                'Name': name,
                'InstanceType': instance['InstanceType'],
                'State': instance['State']['Name']
            })
    return {
        'statusCode': 200,
        'body': json.dumps(instances)
    }

def start_instances(event):
    body = json.loads(event['body'])
    instance_ids = body.get('instanceIds', [])
    if not instance_ids:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'instanceIds is required'})
        }
    ec2_client.start_instances(InstanceIds=instance_ids)
    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'Successfully started instances: {instance_ids}'})
    }

def stop_instances(event):
    body = json.loads(event['body'])
    instance_ids = body.get('instanceIds', [])
    if not instance_ids:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'instanceIds is required'})
        }
    ec2_client.stop_instances(InstanceIds=instance_ids)
    return {
        'statusCode': 200,
        'body': json.dumps({'message': f'Successfully stopped instances: {instance_ids}'})
    }

def tag_instances(event):
    body = json.loads(event['body'])
    instance_ids = body.get('instanceIds', [])
    shift = body.get('shift', '')
    if not instance_ids or not shift:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'instanceIds and shift are required'})
        }
    # If shift is "None", remove the Shift tag; otherwise, set it
    if shift.lower() == 'none':
        ec2_client.delete_tags(
            Resources=instance_ids,
            Tags=[{'Key': 'Shift'}]
        )
        message = f'Successfully removed Shift tag from instances: {instance_ids}'
    else:
        ec2_client.create_tags(
            Resources=instance_ids,
            Tags=[{'Key': 'Shift', 'Value': shift}]
        )
        message = f'Successfully tagged instances with Shift={shift}'
    return {
        'statusCode': 200,
        'body': json.dumps({'message': message})
    }
```

---

## 6. Google Sheets and Apps Script Configuration

### 6.1 Google Sheets Structure
The Google Sheet (`EC2Scheduler`) contains the following sheets:
- **EC2Scheduler**: Main sheet to list and manage EC2 instances.
  - Columns: `Instance ID`, `Name`, `Type`, `Current State`, `Override State`, `Shift`.
- **DefinedShifts**: Defines shift schedules.
  - Columns: `Shift Name`, `Start Time (UTC)`, `End Time (UTC)`.
  - Example data:
    ```
    Shift Name | Start Time (UTC) | End Time (UTC)
    Shift 1    | 00:00           | 04:00
    Shift 2    | 04:00           | 08:00
    ...
    ```
- **CostAnalysis**: Tracks API Gateway usage costs.
  - Columns: `Operation`, `Requests per Month`, `Cost per Month (USD)`.

### 6.2 Google Apps Script Files

#### `googleApps/Code.gs`
This is the main script for managing EC2 operations, notifications, and scheduling.

```javascript
// ec2Scheduler.gs

// Constants
const INSTANCES_URL = "https://your-api-gateway-url/prod/instances"; // Replace with actual URL
const START_URL = "https://your-api-gateway-url/prod/start";
const STOP_URL = "https://your-api-gateway-url/prod/stop";
const TAG_URL = "https://your-api-gateway-url/prod/tag";
const MANAGER_EMAIL = "your-email@example.com"; // Replace with your email
const SCHEDULER_SHEET = "EC2Scheduler";
const SHIFTS_SHEET = "DefinedShifts";
const DEFAULT_SHIFT = "None";
const SHIFT_PROPERTY_KEY = "instanceShifts";

// Google Chat webhook URL
const GOOGLE_CHAT_WEBHOOK_URL = "https://chat.googleapis.com/v1/spaces/XXXX/messages?key=YYYY&token=ZZZZ";

// Slack webhook URL
const SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/TXXXX/BXXXX/XXXX";

// Function to send a notification to Google Chat
function sendChatNotification(message, threadKey = null) {
  try {
    const payload = {
      text: message
    };

    if (threadKey) {
      payload.thread = {
        threadKey: threadKey
      };
    }

    const options = {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    };

    const response = UrlFetchApp.fetch(GOOGLE_CHAT_WEBHOOK_URL, options);
    const responseCode = response.getResponseCode();
    if (responseCode !== 200) {
      Logger.log(`Failed to send notification to Google Chat: ${response.getContentText()}`);
    } else {
      Logger.log(`Notification sent to Google Chat: ${message}`);
    }

    if (!threadKey) {
      const responseData = JSON.parse(response.getContentText());
      return responseData.thread.threadKey;
    }
    return threadKey;
  } catch (e) {
    Logger.log(`Error sending notification to Google Chat: ${e.message}`);
    return threadKey;
  }
}

// Function to send a notification to Slack
function sendSlackNotification(message) {
  try {
    const payload = {
      text: message
    };

    const options = {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    };

    const response = UrlFetchApp.fetch(SLACK_WEBHOOK_URL, options);
    const responseCode = response.getResponseCode();
    if (responseCode !== 200) {
      Logger.log(`Failed to send notification to Slack: ${response.getContentText()}`);
    } else {
      Logger.log(`Notification sent to Slack: ${message}`);
    }
  } catch (e) {
    Logger.log(`Error sending notification to Slack: ${e.message}`);
  }
}

function fetchEC2Instances() {
  try {
    const response = UrlFetchApp.fetch(INSTANCES_URL, { muteHttpExceptions: true });
    handleResponse(response, true);
    updateCostAnalysis();
  } catch (e) {
    Logger.log(`Error fetching instances: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Fetch error: ${e.message}`);
  }
}

function handleResponse(response, setupDropdowns = false) {
  const statusCode = response.getResponseCode();
  const responseText = response.getContentText();
  Logger.log(`Fetch Status: ${statusCode}, Response: ${responseText}`);
  
  if (statusCode !== 200) {
    Logger.log(`Fetch failed with status ${statusCode}: ${responseText}`);
    return;
  }
  
  const instances = JSON.parse(responseText);
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(SCHEDULER_SHEET) || ss.insertSheet(SCHEDULER_SHEET);
  
  sheet.clear();
  sheet.appendRow(["Instance ID", "Name", "Type", "Current State", "Override State", "Shift"]);
  
  const headerRange = sheet.getRange(1, 1, 1, 6);
  headerRange.clearDataValidations();
  
  const shiftsSheet = ss.getSheetByName(SHIFTS_SHEET) || setupShiftsSheet(ss);
  const shiftRangesRaw = shiftsSheet.getRange("A2:A7").getValues().flat().filter(String);
  const shiftRanges = [DEFAULT_SHIFT, ...shiftRangesRaw];
  Logger.log(`Valid shift options: ${shiftRanges}`);
  
  const properties = PropertiesService.getScriptProperties();
  const savedShifts = JSON.parse(properties.getProperty(SHIFT_PROPERTY_KEY) || "{}");
  
  if (setupDropdowns) {
    const shiftHeaderCell = sheet.getRange(1, 6);
    shiftHeaderCell.setDataValidation(SpreadsheetApp.newDataValidation()
      .requireValueInList(shiftRanges, true)
      .setAllowInvalid(false)
      .build());
    const currentHeaderValue = shiftHeaderCell.getValue();
    if (!currentHeaderValue || !shiftRanges.includes(currentHeaderValue)) {
      shiftHeaderCell.setValue(DEFAULT_SHIFT);
      Logger.log(`Reset header shift to default: ${DEFAULT_SHIFT}`);
    }
  }
  
  instances.forEach((instance, index) => {
    const row = index + 2;
    sheet.getRange(row, 1).setValue(instance.InstanceId);
    sheet.getRange(row, 2).setValue(instance.Name || "Unnamed");
    sheet.getRange(row, 3).setValue(instance.InstanceType);
    sheet.getRange(row, 4).setValue(instance.State);
    if (setupDropdowns) {
      const overrideCell = sheet.getRange(row, 5);
      overrideCell.setDataValidation(SpreadsheetApp.newDataValidation()
        .requireValueInList(["", "Start", "Stop"], true)
        .setAllowInvalid(false)
        .build());
      
      const shiftCell = sheet.getRange(row, 6);
      shiftCell.setDataValidation(SpreadsheetApp.newDataValidation()
        .requireValueInList(shiftRanges, true)
        .setAllowInvalid(false)
        .build());
      const headerShift = sheet.getRange(1, 6).getValue();
      let instanceShift = savedShifts[instance.InstanceId] || headerShift;
      if (!shiftRanges.includes(instanceShift)) {
        instanceShift = DEFAULT_SHIFT;
        savedShifts[instance.InstanceId] = DEFAULT_SHIFT;
        Logger.log(`Reset shift for ${instance.InstanceId} to default: ${DEFAULT_SHIFT}`);
      }
      shiftCell.setValue(instanceShift);
    }
  });
  
  properties.setProperty(SHIFT_PROPERTY_KEY, JSON.stringify(savedShifts));
  styleEC2SchedulerSheet(sheet);
}

function setupShiftsSheet(ss) {
  const sheet = ss.insertSheet(SHIFTS_SHEET);
  sheet.appendRow(["Shift Name", "Start Time (UTC)", "End Time (UTC)"]);
  const shifts = [
    ["Shift 1", "00:00", "04:00"],
    ["Shift 2", "04:00", "08:00"],
    ["Shift 3", "08:00", "12:00"],
    ["Shift 4", "12:00", "16:00"],
    ["Shift 5", "16:00", "20:00"],
    ["Shift 6", "20:00", "00:00"]
  ];
  sheet.getRange(2, 1, shifts.length, 3).setValues(shifts);
  styleDefinedShiftsSheet(sheet);
  return sheet;
}

function onSheetEdit(e) {
  const sheet = e.source.getActiveSheet();
  if (sheet.getName() !== SCHEDULER_SHEET) return;
  
  const range = e.range;
  const row = range.getRow();
  const col = range.getColumn();
  const value = range.getValue();
  
  Logger.log(`onSheetEdit triggered: Sheet=${sheet.getName()}, Row=${row}, Col=${col}, Value='${value}'`);
  
  if (row <= 1 && col !== 6) return;
  
  const shiftsSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHIFTS_SHEET);
  const shiftRangesRaw = shiftsSheet.getRange("A2:A7").getValues().flat().filter(String);
  const shiftRanges = [DEFAULT_SHIFT, ...shiftRangesRaw];
  
  if (col === 5 && row > 1) {
    const instanceId = sheet.getRange(row, 1).getValue();
    const overrideState = value;
    Logger.log(`Override State edit: InstanceID=${instanceId}, OverrideState='${overrideState}'`);
    
    if (overrideState === "Start" || overrideState === "Stop") {
      const url = overrideState === "Start" ? START_URL : STOP_URL;
      const payload = JSON.stringify({ instanceIds: [instanceId] });
      const options = { method: "post", contentType: "application/json", payload, muteHttpExceptions: true };
      
      try {
        const response = UrlFetchApp.fetch(url, options);
        const statusCode = response.getResponseCode();
        const responseText = response.getContentText();
        Logger.log(`Response: Status=${statusCode}, Body=${responseText}`);
        
        if (statusCode === 200) {
          range.clear();
          sendEmailNotification(overrideState.toLowerCase(), [instanceId], true);
          fetchEC2Instances();
        } else {
          SpreadsheetApp.getUi().alert(`Failed to ${overrideState} ${instanceId}: ${responseText}`);
          sendEmailNotification(overrideState.toLowerCase(), [instanceId], false);
        }
      } catch (e) {
        Logger.log(`Request error: ${e.message}`);
        SpreadsheetApp.getUi().alert(`Request error: ${e.message}`);
        sendEmailNotification(overrideState.toLowerCase(), [instanceId], false);
      }
    }
  } else if (col === 6 && row === 1) {
    const shiftName = value;
    Logger.log(`Global Shift edit: Attempted Shift='${shiftName}', Valid Options=${shiftRanges}`);
    
    if (!shiftRanges.includes(shiftName)) {
      SpreadsheetApp.getUi().alert(`Invalid shift: '${shiftName}'. Please select from: ${shiftRanges.join(", ")}`);
      range.setValue(DEFAULT_SHIFT);
      return;
    }
    
    const properties = PropertiesService.getScriptProperties();
    const savedShifts = JSON.parse(properties.getProperty(SHIFT_PROPERTY_KEY) || "{}");
    const instanceData = sheet.getRange("A2:A" + sheet.getLastRow()).getValues().flat();
    instanceData.forEach(instanceId => {
      if (instanceId) savedShifts[instanceId] = shiftName;
    });
    properties.setProperty(SHIFT_PROPERTY_KEY, JSON.stringify(savedShifts));
    
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      sheet.getRange(2, 6, lastRow - 1, 1).setValue(shiftName);
      const instanceIds = instanceData.filter(id => id);
      sendShiftUpdateEmail("Global", instanceIds, shiftName);
      
      // Tag all instances with the new shift
      tagEC2Instances(instanceIds, shiftName);
    }
    
    checkShifts();
  } else if (col === 6 && row > 1) {
    const instanceId = sheet.getRange(row, 1).getValue();
    const shiftName = value;
    Logger.log(`Individual Shift edit: InstanceID=${instanceId}, Attempted Shift='${shiftName}', Valid Options=${shiftRanges}`);
    
    if (!shiftRanges.includes(shiftName)) {
      SpreadsheetApp.getUi().alert(`Invalid shift: '${shiftName}'. Please select from: ${shiftRanges.join(", ")}`);
      const savedShifts = JSON.parse(PropertiesService.getScriptProperties().getProperty(SHIFT_PROPERTY_KEY) || "{}");
      range.setValue(savedShifts[instanceId] || DEFAULT_SHIFT);
      return;
    }
    
    const properties = PropertiesService.getScriptProperties();
    const savedShifts = JSON.parse(properties.getProperty(SHIFT_PROPERTY_KEY) || "{}");
    savedShifts[instanceId] = shiftName;
    properties.setProperty(SHIFT_PROPERTY_KEY, JSON.stringify(savedShifts));
    
    sendShiftUpdateEmail("Individual", [instanceId], shiftName);
    
    // Tag the individual instance with the new shift
    tagEC2Instances([instanceId], shiftName);
    
    checkShifts();
  }
}

function tagEC2Instances(instanceIds, shiftName) {
  if (!instanceIds || instanceIds.length === 0) {
    Logger.log("No instance IDs provided for tagging");
    return;
  }
  
  const payload = JSON.stringify({
    instanceIds: instanceIds,
    shift: shiftName
  });
  
  const options = {
    method: "post",
    contentType: "application/json",
    payload: payload,
    muteHttpExceptions: true
  };
  
  try {
    const response = UrlFetchApp.fetch(TAG_URL, options);
    const statusCode = response.getResponseCode();
    const responseText = response.getContentText();
    Logger.log(`Tag request: Status=${statusCode}, Response=${responseText}`);
    
    if (statusCode === 200) {
      Logger.log(`Successfully tagged instances ${instanceIds.join(", ")} with shift ${shiftName}`);
      sendTagUpdateEmail(instanceIds, shiftName, true);
    } else {
      Logger.log(`Failed to tag instances: ${responseText}`);
      SpreadsheetApp.getUi().alert(`Failed to tag instances: ${responseText}`);
      sendTagUpdateEmail(instanceIds, shiftName, false);
    }
  } catch (e) {
    Logger.log(`Tag request error: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Tag request error: ${e.message}`);
    sendTagUpdateEmail(instanceIds, shiftName, false);
  }
}

function sendTagUpdateEmail(instanceIds, shiftName, success) {
  const status = success ? "successfully" : "failed to be";
  const subject = `EC2 Tag Update Notification`;
  const body = `The following EC2 instances were ${status} tagged with Shift=${shiftName} at ${new Date().toUTCString()}:\n\n` +
               `Instance IDs: ${instanceIds.join(", ")}\n` +
               `Region: us-east-1`;
  const message = `🏷️ Tag Update: Instances ${instanceIds.join(", ")} were ${status} tagged with Shift=${shiftName} at ${new Date().toUTCString()} (Region: us-east-1)`;

  try {
    // Send email notification
    MailApp.sendEmail({
      to: MANAGER_EMAIL,
      subject: subject,
      body: body
    });
    Logger.log(`Email sent for tag update: ${subject}`);
    
    // Send Google Chat notification
    const threadKey = PropertiesService.getScriptProperties().getProperty("TAG_THREAD_KEY");
    const newThreadKey = sendChatNotification(message, threadKey);
    
    // Store the threadKey for future tag/shift update messages
    if (!threadKey && newThreadKey) {
      PropertiesService.getScriptProperties().setProperty("TAG_THREAD_KEY", newThreadKey);
    }

    // Send Slack notification
    sendSlackNotification(message);
  } catch (e) {
    Logger.log(`Failed to send tag update notification: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Tag update notification failed: ${e.message}`);
  }
}

function checkShifts() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const schedulerSheet = ss.getSheetByName(SCHEDULER_SHEET);
  const shiftsSheet = ss.getSheetByName(SHIFTS_SHEET);
  if (!schedulerSheet || !shiftsSheet) return;
  
  const now = new Date();
  const utcHours = now.getUTCHours();
  const utcMinutes = now.getUTCMinutes();
  const currentTime = utcHours * 60 + utcMinutes;
  
  const shiftData = shiftsSheet.getRange("A2:C7").getValues();
  const instanceData = schedulerSheet.getRange("A2:F" + schedulerSheet.getLastRow()).getValues();
  
  const activeInstances = [];
  const toStopInstances = [];
  
  instanceData.forEach((row) => {
    const instanceId = row[0];
    const currentState = row[3];
    const shiftName = row[5];
    
    if (currentState === "terminated") return;
    
    if (!shiftName || shiftName === DEFAULT_SHIFT) {
      if (currentState === "running") toStopInstances.push(instanceId);
      return;
    }
    
    const shift = shiftData.find(s => s[0] === shiftName);
    if (!shift) return;
    
    const startTimeStr = String(shift[1]);
    const endTimeStr = String(shift[2]);
    if (!startTimeStr.includes(":") || !endTimeStr.includes(":")) {
      Logger.log(`Invalid time format in shift ${shiftName}: Start='${shift[1]}', End='${shift[2]}'`);
      return;
    }
    
    const [startHour, startMin] = startTimeStr.split(":").map(Number);
    const [endHour, endMin] = endTimeStr.split(":").map(Number);
    const startTime = startHour * 60 + startMin;
    const endTime = endHour * 60 + endMin || 24 * 60;
    
    const isActiveShift = startTime <= currentTime && currentTime < endTime;
    Logger.log(`Shift check: Instance=${instanceId}, Shift=${shiftName}, Time=${currentTime}, Range=${startTime}-${endTime}, Active=${isActiveShift}`);
    
    if (isActiveShift && currentState !== "running") {
      activeInstances.push(instanceId);
    } else if (!isActiveShift && currentState === "running") {
      toStopInstances.push(instanceId);
    }
  });
  
  if (activeInstances.length > 0) {
    sendBulkRequest("start", activeInstances);
  }
  if (toStopInstances.length > 0) {
    sendBulkRequest("stop", toStopInstances);
  }
}

function sendBulkRequest(action, instanceIds) {
  const url = action === "start" ? START_URL : STOP_URL;
  const payload = JSON.stringify({ instanceIds });
  const options = { method: "post", contentType: "application/json", payload, muteHttpExceptions: true };
  
  try {
    const response = UrlFetchApp.fetch(url, options);
    const statusCode = response.getResponseCode();
    const responseText = response.getContentText();
    Logger.log(`Bulk request to ${url}: Status=${statusCode}, Response=${responseText}`);
    
    if (statusCode === 200) {
      sendEmailNotification(action, instanceIds, true);
      fetchEC2Instances();
    } else {
      SpreadsheetApp.getUi().alert(`Bulk ${action} failed: ${responseText}`);
      sendEmailNotification(action, instanceIds, false);
    }
  } catch (e) {
    Logger.log(`Bulk request error: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Bulk request error: ${e.message}`);
    sendEmailNotification(action, instanceIds, false);
  }
}

function sendEmailNotification(action, instanceIds, success) {
  const status = success ? "successfully" : "failed to";
  const subject = `EC2 ${action.capitalize()} Notification`;
  const body = `The following EC2 instances were ${status} ${action}ed at ${new Date().toUTCString()}:\n\n` +
               `Instance IDs: ${instanceIds.join(", ")}\n` +
               `Region: us-east-1`;
  const emoji = action === "start" ? "🚀" : "🛑";
  const message = `${emoji} ${action.capitalize()} Operation: Instances ${instanceIds.join(", ")} were ${status} ${action}ed at ${new Date().toUTCString()} (Region: us-east-1)`;

  try {
    // Send email notification
    MailApp.sendEmail({
      to: MANAGER_EMAIL,
      subject: subject,
      body: body
    });
    Logger.log(`Email sent for ${action}: ${subject}`);
    
    // Send Google Chat notification
    sendChatNotification(message);

    // Send Slack notification
    sendSlackNotification(message);
  } catch (e) {
    Logger.log(`Failed to send notification for ${action}: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Notification failed: ${e.message}`);
  }
}

function sendShiftUpdateEmail(type, instanceIds, shiftName) {
  const subject = `${type} Shift Update Notification`;
  const body = `${type} shift updated at ${new Date().toUTCString()}:\n\n` +
               `Instance IDs: ${instanceIds.join(", ")}\n` +
               `New Shift: ${shiftName}\n` +
               `Region: us-east-1`;
  const message = `🔄 ${type} Shift Update: Instances ${instanceIds.join(", ")} updated to Shift=${shiftName} at ${new Date().toUTCString()} (Region: us-east-1)`;

  try {
    // Send email notification
    MailApp.sendEmail({
      to: MANAGER_EMAIL,
      subject: subject,
      body: body
    });
    Logger.log(`Email sent for ${type.toLowerCase()} shift update: ${subject}`);
    
    // Send Google Chat notification
    const threadKey = PropertiesService.getScriptProperties().getProperty("TAG_THREAD_KEY");
    const newThreadKey = sendChatNotification(message, threadKey);
    
    // Store the threadKey for future tag/shift update messages
    if (!threadKey && newThreadKey) {
      PropertiesService.getScriptProperties().setProperty("TAG_THREAD_KEY", newThreadKey);
    }

    // Send Slack notification
    sendSlackNotification(message);
  } catch (e) {
    Logger.log(`Failed to send shift update notification: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Shift update notification failed: ${e.message}`);
  }
}

function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("EC2 Tools")
    .addItem("Refresh EC2 List", "fetchEC2Instances")
    .addItem("Setup Edit Trigger", "setupEditTrigger")
    .addItem("Setup Shift Trigger", "setupShiftTrigger")
    .addItem("Update Cost Analysis", "updateCostAnalysis")
    .addToUi();
}

function setupRefreshTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "fetchEC2Instances") ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger("fetchEC2Instances")
    .timeBased()
    .everyMinutes(10)
    .create();
}

function setupEditTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "onSheetEdit") ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger("onSheetEdit")
    .forSpreadsheet(SpreadsheetApp.getActive())
    .onEdit()
    .create();
  SpreadsheetApp.getUi().alert("Edit trigger set up successfully!");
}

function setupShiftTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "checkShifts") ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger("checkShifts")
    .timeBased()
    .everyMinutes(1)
    .create();
  SpreadsheetApp.getUi().alert("Shift trigger set up successfully!");
}

String.prototype.capitalize = function() {
  return this.charAt(0).toUpperCase() + this.slice(1);
};
```

#### `googleApps/style.gs`
This script styles the Google Sheets for better readability.

```javascript
function styleEC2SchedulerSheet(sheet) {
  const headerRange = sheet.getRange(1, 1, 1, 6);
  headerRange.setFontWeight("bold").setBackground("#d3d3d3");
  sheet.setFrozenRows(1);
  sheet.setFrozenColumns(1);
  sheet.autoResizeColumns(1, 6);
}

function styleDefinedShiftsSheet(sheet) {
  const headerRange = sheet.getRange(1, 1, 1, 3);
  headerRange.setFontWeight("bold").setBackground("#d3d3d3");
  sheet.setFrozenRows(1);
  sheet.autoResizeColumns(1, 3);
}
```

#### `googleApps/costAnalyzer.gs`
This script estimates and updates API Gateway costs.

```javascript
function updateCostAnalysis() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName("CostAnalysis") || ss.insertSheet("CostAnalysis");
  
  sheet.clear();
  sheet.appendRow(["Operation", "Requests per Month", "Cost per Month (USD)"]);
  
  // API Gateway pricing (us-east-1): $3.50 per million requests
  const costPerMillionRequests = 3.50;
  const requestsPerDay = {
    "List Instances": 144, // Every 10 minutes = 6 times/hour * 24 hours
    "Start/Stop (Shift)": 12, // 6 shifts * 2 (start/stop)
    "Tag Update": 10 // Estimated manual tag updates
  };
  
  let row = 2;
  for (const [operation, dailyRequests] of Object.entries(requestsPerDay)) {
    const monthlyRequests = dailyRequests * 31; // Assuming 31 days
    const cost = (monthlyRequests / 1_000_000) * costPerMillionRequests;
    sheet.getRange(row, 1, 1, 3).setValues([[operation, monthlyRequests, cost.toFixed(2)]]);
    row++;
  }
  
  const headerRange = sheet.getRange(1, 1, 1, 3);
  headerRange.setFontWeight("bold").setBackground("#d3d3d3");
  sheet.setFrozenRows(1);
  sheet.autoResizeColumns(1, 3);
}
```

### 6.3 Configuring Google Apps Script
1. **Open the Script Editor**:
   - In your Google Sheet, go to **Extensions > Apps Script**.

2. **Add the Script Files**:
   - Create three files: `Code.gs`, `style.gs`, and `costAnalyzer.gs`.
   - Copy the respective code into each file.

3. **Replace Placeholder Values**:
   - In `Code.gs`, replace:
     - `INSTANCES_URL`, `START_URL`, `STOP_URL`, `TAG_URL` with the URLs from Terraform outputs.
     - `MANAGER_EMAIL` with the email address for notifications.
     - `GOOGLE_CHAT_WEBHOOK_URL` with your Google Chat webhook URL.
     - `SLACK_WEBHOOK_URL` with your Slack webhook URL.

4. **Deploy the Script**:
   - Click **Deploy > New Deployment**.
   - Select **Library** or **Web App**.
   - Authorize the script (it requires `UrlFetchApp`, `MailApp`, and `SpreadsheetApp` permissions).

### 6.4 Adding the "EC2 Tools" Menu
The `onOpen` function in `Code.gs` creates a custom menu in the Google Sheet:

```javascript
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("EC2 Tools")
    .addItem("Refresh EC2 List", "fetchEC2Instances")
    .addItem("Setup Edit Trigger", "setupEditTrigger")
    .addItem("Setup Shift Trigger", "setupShiftTrigger")
    .addItem("Update Cost Analysis", "updateCostAnalysis")
    .addToUi();
}
```

- **Refresh EC2 List**: Calls `fetchEC2Instances` to update the `EC2Scheduler` sheet with the latest instance data.
- **Setup Edit Trigger**: Calls `setupEditTrigger` to set up an `onEdit` trigger for real-time updates.
- **Setup Shift Trigger**: Calls `setupShiftTrigger` to set up a time-based trigger for shift checks (every minute).
- **Update Cost Analysis**: Calls `updateCostAnalysis` to update the `CostAnalysis` sheet.

### 6.5 Connecting Google Sheets
- **EC2Scheduler Sheet**:
  - Populated by `fetchEC2Instances`, which calls the `/instances` endpoint.
  - Updated by `onSheetEdit` when users change the “Override State” or “Shift” columns.
  - Interacts with `DefinedShifts` to get valid shift options.
- **DefinedShifts Sheet**:
  - Created by `setupShiftsSheet` if it doesn’t exist.
  - Provides shift schedules used by `checkShifts` to determine when to start/stop instances.
- **CostAnalysis Sheet**:
  - Created and updated by `updateCostAnalysis` to estimate API Gateway costs.

---

## 7. Cost Analysis

### 7.1 Estimation
The `updateCostAnalysis` function in `costAnalyzer.gs` estimates API Gateway costs:
- **Pricing**: $3.50 per million requests in `us-east-1`.
- **Requests per Day**:
  - **List Instances**: 144 requests (6 times/hour * 24 hours, every 10 minutes).
  - **Start/Stop (Shift)**: 12 requests (6 shifts * 2 operations).
  - **Tag Update**: 10 requests (estimated manual updates).
- **Monthly Calculation**:
  - Monthly requests = Daily requests * 31 days.
  - Cost = (Monthly requests / 1,000,000) * $3.50.

### 7.2 Updating the CostAnalysis Sheet
- The `CostAnalysis` sheet is updated whenever `updateCostAnalysis` is called (e.g., after `fetchEC2Instances`).
- Example output:
  ```
  Operation         | Requests per Month | Cost per Month (USD)
  List Instances    | 4464              | 0.02
  Start/Stop (Shift)| 372               | 0.00
  Tag Update        | 310               | 0.00
  ```

---

## 8. Notification System Configuration

### 8.1 Email Notifications
- **Configuration**:
  - Uses `MailApp.sendEmail` to send emails to `MANAGER_EMAIL`.
  - Configured in `sendEmailNotification`, `sendTagUpdateEmail`, and `sendShiftUpdateEmail`.
- **Events**:
  - **Start/Stop**: Sent when an instance is started or stopped.
  - **Tag Update**: Sent when an instance is tagged with a `Shift` tag.
  - **Shift Update**: Sent when a shift is updated (global or individual).

### 8.2 Google Chat Notifications
- **Configuration**:
  - Uses `GOOGLE_CHAT_WEBHOOK_URL` to send messages to a Google Chat space.
  - Implemented in `sendChatNotification` with threading support for tag/shift updates.
- **Events**:
  - Same as email notifications.
  - Tag and shift updates are grouped in a single thread using `TAG_THREAD_KEY`.

### 8.3 Slack Notifications
- **Configuration**:
  - Uses `SLACK_WEBHOOK_URL` to send messages to a Slack channel.
  - Implemented in `sendSlackNotification`.
- **Events**:
  - Same as email and Google Chat notifications.
  - Messages are posted as individual messages (no threading).

---

## 9. Best Practices Followed

1. **Infrastructure as Code**:
   - Used Terraform to manage AWS resources, ensuring reproducibility and version control.
   - Organized Terraform code into modules (`api_gateway`, `lambda`) for modularity.

2. **Security**:
   - IAM role for Lambda has least privilege permissions (e.g., specific EC2 actions).
   - Webhook URLs are placeholders in the code; they should be stored securely in production (e.g., using environment variables or Google Apps Script properties).

3. **Error Handling**:
   - Comprehensive error handling in both the Lambda function and Google Apps Script.
   - Logs errors using `Logger.log` and displays alerts to users via `SpreadsheetApp.getUi().alert`.

4. **Modularity**:
   - Separated Google Apps Script into multiple files (`Code.gs`, `style.gs`, `costAnalyzer.gs`) for better organization.
   - Used constants for configuration values (e.g., URLs, sheet names).

5. **User Experience**:
   - Added a custom “EC2 Tools” menu for easy access to actions.
   - Styled sheets for better readability.
   - Provided dropdowns for “Override State” and “Shift” columns to prevent invalid inputs.

6. **Cost Optimization**:
   - Estimated API Gateway costs to monitor usage.
   - Scheduled operations (e.g., `fetchEC2Instances` every 10 minutes) to balance freshness and cost.

7. **Notifications**:
   - Used multiple channels (email, Google Chat, Slack) for redundancy.
   - Grouped tag/shift updates in Google Chat threads to reduce clutter.

---

## 10. Running the Project

1. **Deploy AWS Infrastructure**:
   - Follow the steps in Section 4.2 to deploy the Terraform configuration.
   - Note the API Gateway URLs from the outputs.

2. **Configure Google Apps Script**:
   - Update `Code.gs` with the API Gateway URLs, email, and webhook URLs.
   - Deploy the script (Section 6.3).

3. **Set Up Triggers**:
   - Open the Google Sheet.
   - Go to **EC2 Tools > Setup Edit Trigger** to enable real-time updates.
   - Go to **EC2 Tools > Setup Shift Trigger** to enable shift-based scheduling.

4. **Interact with the Sheet**:
   - Go to **EC2 Tools > Refresh EC2 List** to populate the `EC2Scheduler` sheet.
   - Change the “Override State” column to `Start` or `Stop` to control instances.
   - Change the “Shift” column to assign a shift (e.g., `Shift 1`).
   - Update the global shift in the header (row 1, column 6) to apply a shift to all instances.

5. **Monitor Notifications**:
   - Check your email, Google Chat space, and Slack channel for notifications.

---

## 11. Troubleshooting

- **Terraform Deployment Fails**:
  - Check AWS credentials and permissions.
  - Ensure the `lambda-ec2.zip` file exists in the `terraform` directory.
- **API Gateway Requests Fail**:
  - Verify the Lambda function has the correct IAM permissions.
  - Check CloudWatch logs for the Lambda function.
- **Google Apps Script Errors**:
  - Check the Apps Script logs (View > Stackdriver Logging).
  - Ensure the API Gateway URLs and webhook URLs are correct.
- **Notifications Not Sent**:
  - Verify the webhook URLs and email address.
  - Check rate limits for Google Chat and Slack.

---

## 12. Future Improvements

- **Authentication**:
  - Add API Gateway authentication (e.g., API keys or IAM roles).
- **Enhanced Security**:
  - Scope down IAM permissions to specific EC2 resources.
  - Store sensitive data (e.g., webhook URLs) in a secure vault.
- **Advanced Scheduling**:
  - Allow more flexible shift schedules (e.g., per-day schedules).
- **Cost Optimization**:
  - Reduce the frequency of `fetchEC2Instances` if costs increase.
- **Monitoring**:
  - Add CloudWatch alarms for Lambda errors or API Gateway usage.

---

This documentation provides a detailed guide to setting up, configuring, and running the EC2 Scheduler project. Follow the steps to deploy the infrastructure, configure the Google Sheet, and manage your EC2 instances efficiently.
