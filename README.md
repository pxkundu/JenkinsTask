# EC2 List Project (JenkinsTask)

This project creates a Google Sheet to list AWS EC2 instances with ID, Name, Type, and Current State (color-coded) using AWS Lambda, API Gateway, Terraform, and Google Apps Script.

## Setup Instructions
1. **Package Lambda**:
   - Navigate to `lambda/`
   - Zip the contents: `zip -r ../terraform/lambda-ec2.zip .`

2. **Deploy Infrastructure**:
   - Navigate to `terraform/`
   - Run `terraform init` and `terraform apply`
   - Note the `api_url` output

3. **Google Apps Script**:
   - Open a Google Sheet
   - Go to `Extensions > Apps Script`
   - Paste the script below
   - Replace `<replace-with-terraform-api-url>` with the Terraform `api_url` output
   - Save and run

## Google Apps Script Code
```javascript
function fetchEC2Instances() {
  const apiUrl = "<replace-with-terraform-api-url>";
  const response = UrlFetchApp.fetch(apiUrl);
  const instances = JSON.parse(response.getContentText());
  const sheet = SpreadsheetApp.getActiveSheet();
  sheet.clear();
  sheet.appendRow(["Instance ID", "Name", "Type", "Current State"]);
  instances.forEach((instance, index) => {
    const row = index + 2;
    sheet.getRange(row, 1).setValue(instance.InstanceId);
    sheet.getRange(row, 2).setValue(instance.Name);
    sheet.getRange(row, 3).setValue(instance.InstanceType);
    sheet.getRange(row, 4).setValue(instance.State);
    const stateCell = sheet.getRange(row, 4);
    switch (instance.State) {
      case "running":
        stateCell.setBackground("#00FF00"); // Green
        break;
      case "stopped":
        stateCell.setBackground("#FF0000"); // Red
        break;
      case "pending":
        stateCell.setBackground("#FFFF00"); // Yellow
        break;
      case "stopping":
        stateCell.setBackground("#FFA500"); // Orange
        break;
      default:
        stateCell.setBackground("#808080"); // Gray
    }
  });
}

function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("EC2 Tools")
    .addItem("Refresh EC2 List", "fetchEC2Instances")
    .addToUi();
}
