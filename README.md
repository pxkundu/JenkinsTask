Below is a detailed, step-by-step documentation guide for setting up the EC2 Start/Stop Automation project using AWS, Terraform, and Google Apps Script, as we’ve developed it. This covers everything from initializing the project folder structure to configuring AWS, Terraform, and Google Sheets, including all code and commands. The goal is to provide a comprehensive walkthrough that anyone can follow to replicate the setup.

---

# EC2 Start/Stop Automation Project Documentation

This project automates the starting and stopping of EC2 instances based on predefined shifts, notifies a manager via Gmail, tracks instance states in Google Sheets, and provides cost analysis. It uses AWS for infrastructure, Terraform for provisioning, and Google Apps Script for scheduling and notifications.

---

## Step 1: Project Repo clone
**Clone Repo**:
   - Open a terminal (e.g., Command Prompt, Terminal, or VS Code Terminal).
     ```bash
     git clone [<THIS REPO URL>](https://github.com/pxkundu/JenkinsTask.git)
     Checkout to [<THIS BRANCH>](https://github.com/pxkundu/JenkinsTask/tree/feature/AWS-account-automation)
     ```

### Project Folder Structure
```
JenkinsTask/
├── lambda/
│   ├── main.py
│   └── requirements.txt
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── lambda-ec2.zip  (generated)
│   └── modules/
│       ├── lambda/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── api_gateway/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── script.gs
├── .gitignore
└── README.md
```

---

## Step 2: AWS Configuration

### Objective
Configure AWS credentials and permissions to allow Terraform and Google Apps Script to manage EC2 instances.

### Prerequisites
- AWS account with administrative access.
- AWS CLI installed (`aws --version` to check; if not installed, run `pip install awscli` or download from AWS).

### Steps
1. **Install AWS CLI** (if not already installed):
   - On macOS/Linux:
     ```bash
     curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
     sudo installer -pkg AWSCLIV2.pkg -target /
     ```
   - On Windows:
     - Download from [AWS CLI Installer](https://awscli.amazonaws.com/AWSCLIV2.msi) and run the installer.

2. **Configure AWS CLI**:
   - Run the configuration command:
     ```bash
     aws configure
     ```
   - Enter your AWS Access Key ID, Secret Access Key, region (e.g., `us-east-1`), and output format (e.g., `json`):
     ```
     AWS Access Key ID: YOUR_ACCESS_KEY
     AWS Secret Access Key: YOUR_SECRET_KEY
     Default region name: us-east-1
     Default output format: json
     ```

3. **Create an IAM Role for API Gateway**:
   - Log in to the AWS Management Console.
   - Go to IAM > Roles > Create Role.
   - Select "AWS Service" > "API Gateway" > Next.
   - Attach policies:
     - `AmazonEC2FullAccess`
   - Name the role `APIGatewayEC2Role`.
   - Create the role and note the ARN (e.g., `arn:aws:iam::123456789012:role/APIGatewayEC2Role`).

4. **Test AWS CLI**:
   - Verify access by listing EC2 instances:
     ```bash
     aws ec2 describe-instances --region us-east-1
     ```
   - If successful, you’ll see a JSON response with instance details.

---

## Step 3: Terraform Configuration

### Objective
Use Terraform to provision an API Gateway with endpoints to start, stop, and list EC2 instances.

### Prerequisites
- Terraform installed (`terraform -v` to check; if not installed, download from [Terraform](https://www.terraform.io/downloads.html)).

### Steps
1. **Navigate to Terraform Directory**:
   ```bash
   cd terraform
   ```

2. **Initialize Terraform**:
   - Create a Terraform configuration file:
     ```bash
     touch main.tf
     ```
   - Initialize the Terraform working directory:
     ```bash
     terraform init
     ```

3. **Write Terraform Configuration**:
   - Edit `main.tf` with the following code to set up API Gateway with Lambda integration:
     ```hcl
     provider "aws" {
       region = "us-east-1"
     }

     # Lambda function to manage EC2 instances
     resource "aws_lambda_function" "ec2_manager" {
       filename      = "lambda.zip"
       function_name = "ec2Manager"
       role          = "arn:aws:iam::YOUR_ACCOUNT_ID:role/APIGatewayEC2Role"
       handler       = "lambda_function.lambda_handler"
       runtime       = "python3.9"
       source_code_hash = filebase64sha256("lambda.zip")
     }

     # API Gateway
     resource "aws_api_gateway_rest_api" "ec2_api" {
       name = "EC2ControlAPI"
     }

     resource "aws_api_gateway_resource" "instances" {
       rest_api_id = aws_api_gateway_rest_api.ec2_api.id
       parent_id   = aws_api_gateway_rest_api.ec2_api.root_resource_id
       path_part   = "instances"
     }

     resource "aws_api_gateway_resource" "start" {
       rest_api_id = aws_api_gateway_rest_api.ec2_api.id
       parent_id   = aws_api_gateway_rest_api.ec2_api.root_resource_id
       path_part   = "start"
     }

     resource "aws_api_gateway_resource" "stop" {
       rest_api_id = aws_api_gateway_rest_api.ec2_api.id
       parent_id   = aws_api_gateway_rest_api.ec2_api.root_resource_id
       path_part   = "stop"
     }

     # Methods
     resource "aws_api_gateway_method" "instances_get" {
       rest_api_id   = aws_api_gateway_rest_api.ec2_api.id
       resource_id   = aws_api_gateway_resource.instances.id
       http_method   = "GET"
       authorization = "NONE"
     }

     resource "aws_api_gateway_method" "start_post" {
       rest_api_id   = aws_api_gateway_rest_api.ec2_api.id
       resource_id   = aws_api_gateway_resource.start.id
       http_method   = "POST"
       authorization = "NONE"
     }

     resource "aws_api_gateway_method" "stop_post" {
       rest_api_id   = aws_api_gateway_rest_api.ec2_api.id
       resource_id   = aws_api_gateway_resource.stop.id
       http_method   = "POST"
       authorization = "NONE"
     }

     # Lambda Integrations
     resource "aws_api_gateway_integration" "instances_integration" {
       rest_api_id             = aws_api_gateway_rest_api.ec2_api.id
       resource_id             = aws_api_gateway_resource.instances.id
       http_method             = aws_api_gateway_method.instances_get.http_method
       integration_http_method = "POST"
       type                    = "AWS_PROXY"
       uri                     = aws_lambda_function.ec2_manager.invoke_arn
     }

     resource "aws_api_gateway_integration" "start_integration" {
       rest_api_id             = aws_api_gateway_rest_api.ec2_api.id
       resource_id             = aws_api_gateway_resource.start.id
       http_method             = aws_api_gateway_method.start_post.http_method
       integration_http_method = "POST"
       type                    = "AWS_PROXY"
       uri                     = aws_lambda_function.ec2_manager.invoke_arn
     }

     resource "aws_api_gateway_integration" "stop_integration" {
       rest_api_id             = aws_api_gateway_rest_api.ec2_api.id
       resource_id             = aws_api_gateway_resource.stop.id
       http_method             = aws_api_gateway_method.stop_post.http_method
       integration_http_method = "POST"
       type                    = "AWS_PROXY"
       uri                     = aws_lambda_function.ec2_manager.invoke_arn
     }

     # Deployment
     resource "aws_api_gateway_deployment" "ec2_api_deployment" {
       depends_on = [
         aws_api_gateway_integration.instances_integration,
         aws_api_gateway_integration.start_integration,
         aws_api_gateway_integration.stop_integration
       ]
       rest_api_id = aws_api_gateway_rest_api.ec2_api.id
       stage_name  = "prod"
     }

     # Lambda Permission
     resource "aws_lambda_permission" "api_gateway" {
       statement_id  = "AllowAPIGatewayInvoke"
       action        = "lambda:InvokeFunction"
       function_name = aws_lambda_function.ec2_manager.function_name
       principal     = "apigateway.amazonaws.com"
       source_arn    = "${aws_api_gateway_rest_api.ec2_api.execution_arn}/*/*"
     }

     output "api_url" {
       value = aws_api_gateway_deployment.ec2_api_deployment.invoke_url
     }
     ```
   - Replace `YOUR_ACCOUNT_ID` with your AWS account ID (from IAM or CLI output).

4. **Create Lambda Function Code**:
   - Create `lambda_function.py` in the `terraform` directory:
     ```python
     import boto3
     import json

     ec2_client = boto3.client('ec2', region_name='us-east-1')

     def lambda_handler(event, context):
         http_method = event['httpMethod']
         path = event['path']

         if path == '/instances' and http_method == 'GET':
             response = ec2_client.describe_instances()
             instances = []
             for reservation in response['Reservations']:
                 for instance in reservation['Instances']:
                     instances.append({
                         'InstanceId': instance['InstanceId'],
                         'Name': next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed'),
                         'InstanceType': instance['InstanceType'],
                         'State': instance['State']['Name']
                     })
             return {'statusCode': 200, 'body': json.dumps(instances)}

         elif path == '/start' and http_method == 'POST':
             body = json.loads(event['body'])
             instance_ids = body.get('instanceIds', [])
             ec2_client.start_instances(InstanceIds=instance_ids)
             return {'statusCode': 200, 'body': json.dumps({'message': 'Instances started'})}

         elif path == '/stop' and http_method == 'POST':
             body = json.loads(event['body'])
             instance_ids = body.get('instanceIds', [])
             ec2_client.stop_instances(InstanceIds=instance_ids)
             return {'statusCode': 200, 'body': json.dumps({'message': 'Instances stopped'})}

         return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid request'})}
     ```
   - Zip the file:
     ```bash
     zip lambda.zip lambda_function.py
     ```

5. **Apply Terraform Configuration**:
   - Plan the deployment:
     ```bash
     terraform plan
     ```
   - Apply the changes:
     ```bash
     terraform apply -auto-approve
     ```
   - Note the `api_url` output (e.g., `https://h7q13ral35.execute-api.us-east-1.amazonaws.com/prod`).

6. **Test API Endpoints**:
   - Fetch instances:
     ```bash
     curl https://YOUR_API_URL/prod/instances
     ```
   - Start an instance (replace `i-123` with a real ID):
     ```bash
     curl -X POST -d '{"instanceIds": ["i-123"]}' https://YOUR_API_URL/prod/start
     ```
   - Stop an instance:
     ```bash
     curl -X POST -d '{"instanceIds": ["i-123"]}' https://YOUR_API_URL/prod/stop
     ```

---

## Step 4: Google Sheets Configuration

### Objective
Set up Google Sheets with Apps Script to manage shifts, update instance states, send emails, and calculate costs.

### Prerequisites
- Google account with access to Google Sheets and Apps Script.

### Steps
1. **Create a Google Sheet**:
   - Go to [Google Sheets](https://sheets.google.com).
   - Click "Blank" to create a new spreadsheet.
   - Name it "EC2Automation" (File > Rename).

2. **Open Apps Script**:
   - In the spreadsheet, go to Extensions > Apps Script.
   - Rename the project to "EC2Automation" in the editor.

3. **Add Apps Script Code**:
   - Replace the default `Code.gs` content with the following:
     ```javascript
     const BASE_URL = "https://YOUR_API_URL/prod"; // From Terraform output
     const INSTANCES_URL = `${BASE_URL}/instances`;
     const START_URL = `${BASE_URL}/start`;
     const STOP_URL = `${BASE_URL}/stop`;

     const SCHEDULER_SHEET = "EC2Scheduler";
     const SHIFTS_SHEET = "DefinedShifts";
     const COST_SHEET = "CostAnalysis";
     const DEFAULT_SHIFT = "None";
     const SHIFT_PROPERTY_KEY = "instanceShifts";
     const MANAGER_EMAIL = "manager@example.com"; // Replace with actual email

     const EC2_HOURLY_RATE = 0.0416;
     const API_CALL_COST = 0.001;
     const HOURS_PER_MONTH = 730;

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
         
         const stateCell = sheet.getRange(row, 4);
         switch (instance.State) {
           case "running": stateCell.setBackground("#00FF00"); break;
           case "stopped": stateCell.setBackground("#FF0000"); break;
           case "pending": stateCell.setBackground("#FFFF00"); break;
           case "stopping": stateCell.setBackground("#FFA500"); break;
           case "terminated": stateCell.setBackground("#808080"); break;
           default: stateCell.setBackground("#D3D3D3");
         }
         
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
         checkShifts();
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
       try {
         MailApp.sendEmail({
           to: MANAGER_EMAIL,
           subject: subject,
           body: body
         });
         Logger.log(`Email sent for ${action}: ${subject}`);
       } catch (e) {
         Logger.log(`Failed to send email for ${action}: ${e.message}`);
         SpreadsheetApp.getUi().alert(`Email notification failed: ${e.message}`);
       }
     }

     function sendShiftUpdateEmail(type, instanceIds, shiftName) {
       const subject = `${type} Shift Update Notification`;
       const body = `${type} shift updated at ${new Date().toUTCString()}:\n\n` +
                    `Instance IDs: ${instanceIds.join(", ")}\n` +
                    `New Shift: ${shiftName}\n` +
                    `Region: us-east-1`;
       try {
         MailApp.sendEmail({
           to: MANAGER_EMAIL,
           subject: subject,
           body: body
         });
         Logger.log(`Email sent for ${type.toLowerCase()} shift update: ${subject}`);
       } catch (e) {
         Logger.log(`Failed to send shift update email: ${e.message}`);
         SpreadsheetApp.getUi().alert(`Shift update email failed: ${e.message}`);
       }
     }

     function updateCostAnalysis() {
       const ss = SpreadsheetApp.getActiveSpreadsheet();
       let costSheet = ss.getSheetByName(COST_SHEET);
       if (!costSheet) {
         costSheet = ss.insertSheet(COST_SHEET);
       }
       costSheet.clear();
       costSheet.appendRow(["Category", "Subcategory", "Description", "Cost ($)"]);
       
       const schedulerSheet = ss.getSheetByName(SCHEDULER_SHEET);
       const shiftsSheet = ss.getSheetByName(SHIFTS_SHEET);
       if (!schedulerSheet || !shiftsSheet) return;
       
       const runsPerDay = 24 * 60;
       const fetchCallsPerDay = 24 * 6;
       const startStopCallsPerDay = runsPerDay * 2;
       
       const fetchCostDaily = fetchCallsPerDay * API_CALL_COST;
       const startCostDaily = runsPerDay * API_CALL_COST;
       const stopCostDaily = runsPerDay * API_CALL_COST;
       
       const monthlyFetchCost = fetchCostDaily * 30;
       const monthlyStartCost = startCostDaily * 30;
       const monthlyStopCost = stopCostDaily * 30;
       const totalAutomationCost = monthlyFetchCost + monthlyStartCost + monthlyStopCost;
       
       costSheet.appendRow(["Automation", "Fetch Instances", `Monthly cost of ${fetchCallsPerDay} daily API calls`, monthlyFetchCost.toFixed(2)]);
       costSheet.appendRow(["Automation", "Start Instances", `Monthly cost of ${runsPerDay} daily API calls`, monthlyStartCost.toFixed(2)]);
       costSheet.appendRow(["Automation", "Stop Instances", `Monthly cost of ${runsPerDay} daily API calls`, monthlyStopCost.toFixed(2)]);
       costSheet.appendRow(["Automation", "Total", "Total monthly automation cost", totalAutomationCost.toFixed(2)]);
       
       const shiftData = shiftsSheet.getRange("A2:C7").getValues();
       const instanceData = schedulerSheet.getRange("A2:F" + schedulerSheet.getLastRow()).getValues();
       
       let totalEC2Cost = 0;
       instanceData.forEach(row => {
         const instanceId = row[0];
         const shiftName = row[5];
         if (shiftName && shiftName !== DEFAULT_SHIFT && row[3] !== "terminated") {
           const shift = shiftData.find(s => s[0] === shiftName);
           if (shift) {
             const startTimeStr = String(shift[1]);
             const endTimeStr = String(shift[2]);
             if (!startTimeStr.includes(":") || !endTimeStr.includes(":")) {
               Logger.log(`Skipping invalid shift ${shiftName} for ${instanceId}: Start='${shift[1]}', End='${shift[2]}'`);
               return;
             }
             
             const [startHour, startMin] = startTimeStr.split(":").map(Number);
             const [endHour, endMin] = endTimeStr.split(":").map(Number);
             const shiftHours = (endHour * 60 + endMin - (startHour * 60 + startMin)) / 60 || 24;
             const dailyCost = shiftHours * EC2_HOURLY_RATE;
             const monthlyCost = dailyCost * 30;
             totalEC2Cost += monthlyCost;
             costSheet.appendRow(["EC2 Instances", instanceId, `Monthly cost for ${shiftHours} hours/day (${shiftName})`, monthlyCost.toFixed(2)]);
           }
         }
       });
       
       costSheet.appendRow(["EC2 Instances", "Total", "Total monthly EC2 cost", totalEC2Cost.toFixed(2)]);
       
       const grandTotal = totalAutomationCost + totalEC2Cost;
       costSheet.appendRow(["Grand Total", "", "Total monthly cost", grandTotal.toFixed(2)]);
       
       costSheet.autoResizeColumns(1, 4);
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
   - Replace `YOUR_API_URL` with the Terraform output (e.g., `https://h7q13ral35.execute-api.us-east-1.amazonaws.com`).
   - Replace `manager@example.com` with the actual email address.

4. **Authorize the Script**:
   - Save the script (File > Save).
   - Run `onOpen` manually:
     - Click the play button next to `onOpen`.
     - Grant permissions for Google Sheets and Gmail access when prompted.

5. **Set Up Triggers**:
   - Go to Triggers (clock icon) in Apps Script.
   - Add triggers manually if not using menu:
     - Click "Add Trigger":
       - Function: `fetchEC2Instances`, Event: Time-driven, Every 10 minutes.
       - Function: `checkShifts`, Event: Time-driven, Every 1 minute.
       - Function: `onSheetEdit`, Event: From spreadsheet, On edit.
   - Alternatively, use the "EC2 Tools" menu:
     - Reload the sheet, go to "EC2 Tools > Setup Edit Trigger".
     - "EC2 Tools > Setup Shift Trigger".
     - "EC2 Tools > Setup Refresh Trigger".

6. **Test the Setup**:
   - Run "EC2 Tools > Refresh EC2 List":
     - "EC2Scheduler" sheet should populate with instance data.
     - "DefinedShifts" sheet should appear with shift definitions.
     - "CostAnalysis" sheet should show cost breakdown.
   - Set F1 to "Shift 5" → Email sent, instances update based on time.
   - Set F2 to "Shift 2" → Email sent for that instance.

---

## Step 5: Final Verification

### Objective
Ensure all features work as expected.

### Steps
1. **Check Instance State Updates**:
   - Verify "EC2Scheduler" column D updates with instance states (green for "running", red for "stopped").
   - Test override (column E): Set to "Start" or "Stop", confirm state change and email.

2. **Validate Shift Scheduling**:
   - Set a shift (e.g., "Shift 5" for 16:00–20:00 UTC).
   - Check logs during shift time (e.g., 17:00 UTC):
     ```
     Shift check: Instance=i-011fc7f8492bc03be, Shift=Shift 5, Time=1020, Range=960-1200, Active=true
     ```

3. **Confirm Email Notifications**:
   - Global shift update (F1):
     ```
     Subject: Global Shift Update Notification
     Body: Global shift updated at Thu, 20 Mar 2025 12:00:00 GMT:
           Instance IDs: i-011fc7f8492bc03be
           New Shift: Shift 5
           Region: us-east-1
     ```
   - Start action:
     ```
     Subject: EC2 Start Notification
     Body: The following EC2 instances were successfully started at Thu, 20 Mar 2025 16:00:00 GMT:
           Instance IDs: i-011fc7f8492bc03be
           Region: us-east-1
     ```

4. **Review Cost Analysis**:
   - "CostAnalysis" should show:
     ```
     Category       | Subcategory           | Description                             | Cost ($)
     Automation     | Fetch Instances      | Monthly cost of 144 daily API calls     | 4.32
     Automation     | Start Instances      | Monthly cost of 1440 daily API calls    | 43.20
     Automation     | Stop Instances       | Monthly cost of 1440 daily API calls    | 43.20
     Automation     | Total                | Total monthly automation cost           | 90.72
     EC2 Instances  | i-011fc7f8492bc03be  | Monthly cost for 4 hours/day (Shift 5)  | 4.99
     EC2 Instances  | Total                | Total monthly EC2 cost                  | 4.99
     Grand Total    |                      | Total monthly cost                      | 95.71
     ```

---

## Troubleshooting

- **AWS Errors**:
  - "Access Denied": Check IAM role permissions and AWS CLI credentials.
  - Run `aws sts get-caller-identity` to verify identity.

- **Terraform Issues**:
  - "Lambda zip not found": Ensure `lambda.zip` is in the `terraform` directory.
  - Rerun `terraform apply`.

- **Google Sheets Errors**:
  - "shift[1].split is not a function": Verify "DefinedShifts" has "HH:MM" format in columns B and C.
  - Reset: Delete "DefinedShifts" sheet and rerun `fetchEC2Instances`.

- **Email Not Sending**:
  - Check Google account’s email quota (100/day free, 1500/day Workspace).
  - Verify `MANAGER_EMAIL` is correct.

---

## Conclusion
This setup provides a fully automated EC2 management system with shift-based scheduling, Gmail notifications, and cost tracking, all integrated via Google Sheets. The project leverages AWS for infrastructure, Terraform for provisioning, and Google Apps Script for orchestration, making it both scalable and cost-effective.
