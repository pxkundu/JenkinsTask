// API Endpoints (replace with Terraform outputs)
const BASE_URL = "https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod";

const INSTANCES_URL = `${BASE_URL}/instances`;
const START_URL = `${BASE_URL}/start`;
const STOP_URL = `${BASE_URL}/stop`;

function fetchEC2Instances() {
  try {
    const response = UrlFetchApp.fetch(INSTANCES_URL, { muteHttpExceptions: true });
    handleResponse(response, true);
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
  const sheet = SpreadsheetApp.getActiveSheet();
  sheet.clear();
  sheet.appendRow(["Instance ID", "Name", "Type", "Current State", "Override State"]);
  
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
      default: stateCell.setBackground("#808080");
    }
    
    if (setupDropdowns) {
      const overrideCell = sheet.getRange(row, 5);
      const rule = SpreadsheetApp.newDataValidation()
        .requireValueInList(["", "Start", "Stop"], true)
        .setAllowInvalid(false)
        .build();
      overrideCell.setDataValidation(rule);
    }
  });
}

// Installable trigger function for edit events
function onSheetEdit(e) {
  const sheet = e.source.getActiveSheet();
  const range = e.range;
  const row = range.getRow();
  const col = range.getColumn();
  const value = range.getValue();
  
  Logger.log(`onSheetEdit triggered: Row=${row}, Col=${col}, Value='${value}'`);
  
  if (col !== 5 || row <= 1) {
    Logger.log(`Edit ignored: Not in Override State column (Col=${col}) or header row (Row=${row})`);
    return;
  }
  
  const instanceId = sheet.getRange(row, 1).getValue();
  const overrideState = value;
  
  Logger.log(`Override State edit: InstanceID=${instanceId}, OverrideState='${overrideState}'`);
  
  if (overrideState !== "Start" && overrideState !== "Stop") {
    Logger.log(`Invalid Override State: '${overrideState}' - No action taken`);
    return;
  }
  
  const url = overrideState === "Start" ? START_URL : STOP_URL;
  const payload = JSON.stringify({ instanceId });
  const options = {
    method: "post",
    contentType: "application/json",
    payload: payload,
    muteHttpExceptions: true
  };
  
  Logger.log(`Sending request: URL=${url}, Payload=${payload}`);
  
  try {
    const response = UrlFetchApp.fetch(url, options);
    const statusCode = response.getResponseCode();
    const responseText = response.getContentText();
    
    Logger.log(`Response: Status=${statusCode}, Body=${responseText}`);
    
    if (statusCode === 200) {
      Logger.log(`Success: ${overrideState} for ${instanceId}`);
      range.clear();
      fetchEC2Instances();
    } else {
      Logger.log(`Failed: Status=${statusCode}, Response=${responseText}`);
      SpreadsheetApp.getUi().alert(`Failed to ${overrideState} ${instanceId}: ${responseText}`);
    }
  } catch (e) {
    Logger.log(`Request error: ${e.message}`);
    SpreadsheetApp.getUi().alert(`Request error: ${e.message}`);
  }
}

function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("EC2 Tools")
    .addItem("Refresh EC2 List", "fetchEC2Instances")
    .addItem("Setup Edit Trigger", "setupEditTrigger")
    .addToUi();
}

function setupRefreshTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "fetchEC2Instances") {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  ScriptApp.newTrigger("fetchEC2Instances")
    .timeBased()
    .everyMinutes(10)
    .create();
}

function setupEditTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === "onSheetEdit") {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  ScriptApp.newTrigger("onSheetEdit")
    .forSpreadsheet(SpreadsheetApp.getActive())
    .onEdit()
    .create();
  SpreadsheetApp.getUi().alert("Edit trigger set up successfully!");
}
