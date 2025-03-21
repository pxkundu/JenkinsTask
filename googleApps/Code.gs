// API Endpoints (replace with Terraform outputs)
const BASE_URL = "https://<<API_ID>>.execute-api.us-east-1.amazonaws.com/prod";


const INSTANCES_URL = `${BASE_URL}/instances`;
const START_URL = `${BASE_URL}/start`;
const STOP_URL = `${BASE_URL}/stop`;

const SCHEDULER_SHEET = "EC2Scheduler";
const SHIFTS_SHEET = "DefinedShifts";
const DEFAULT_SHIFT = "None";
const SHIFT_PROPERTY_KEY = "instanceShifts";
const MANAGER_EMAIL = "partha.kundu@techconsulting.tech"; // Replace with actual email

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
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(SCHEDULER_SHEET) || ss.insertSheet(SCHEDULER_SHEET);
  sheet.clear();
  sheet.appendRow(["Instance ID", "Name", "Type", "Current State", "Override State", "Shift"]);
  
  const shiftsSheet = ss.getSheetByName(SHIFTS_SHEET) || setupShiftsSheet(ss);
  const shiftRangesRaw = shiftsSheet.getRange("A2:A7").getValues().flat().filter(String);
  const shiftRanges = [DEFAULT_SHIFT, ...shiftRangesRaw];
  Logger.log(`Shift options: ${shiftRanges}`);
  
  const properties = PropertiesService.getScriptProperties();
  const savedShifts = JSON.parse(properties.getProperty(SHIFT_PROPERTY_KEY) || "{}");
  
  if (setupDropdowns) {
    const shiftHeaderCell = sheet.getRange(1, 6); // F1
    shiftHeaderCell.setDataValidation(SpreadsheetApp.newDataValidation()
      .requireValueInList(shiftRanges, true)
      .setAllowInvalid(false)
      .build());
    const currentHeaderValue = shiftHeaderCell.getValue();
    if (!currentHeaderValue || !shiftRanges.includes(currentHeaderValue)) {
      shiftHeaderCell.setValue(DEFAULT_SHIFT);
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
        Logger.log(`Invalid saved shift for ${instance.InstanceId}: ${instanceShift}, defaulting to ${DEFAULT_SHIFT}`);
        instanceShift = DEFAULT_SHIFT;
        savedShifts[instance.InstanceId] = DEFAULT_SHIFT;
      }
      shiftCell.setValue(instanceShift);
      Logger.log(`Set shift for ${instance.InstanceId} to: ${instanceShift}`);
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
  
  if (col === 5 && row > 1) { // Override State
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
  } else if (col === 6 && row === 1) { // Global Shift
    const shiftName = value;
    Logger.log(`Global Shift edit: Shift='${shiftName}'`);
    
    if (!shiftRanges.includes(shiftName)) {
      SpreadsheetApp.getUi().alert(`Invalid shift: ${shiftName}.`);
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
    }
    
    checkShifts();
  } else if (col === 6 && row > 1) { // Individual Shift
    const instanceId = sheet.getRange(row, 1).getValue();
    const shiftName = value;
    Logger.log(`Individual Shift edit: InstanceID=${instanceId}, Shift='${shiftName}'`);
    
    if (!shiftRanges.includes(shiftName)) {
      SpreadsheetApp.getUi().alert(`Invalid shift: ${shiftName}.`);
      const savedShifts = JSON.parse(PropertiesService.getScriptProperties().getProperty(SHIFT_PROPERTY_KEY) || "{}");
      range.setValue(savedShifts[instanceId] || DEFAULT_SHIFT);
      return;
    }
    
    const properties = PropertiesService.getScriptProperties();
    const savedShifts = JSON.parse(properties.getProperty(SHIFT_PROPERTY_KEY) || "{}");
    savedShifts[instanceId] = shiftName;
    properties.setProperty(SHIFT_PROPERTY_KEY, JSON.stringify(savedShifts));
    
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
    
    const [startHour, startMin] = shift[1].split(":").map(Number);
    const [endHour, endMin] = shift[2].split(":").map(Number);
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
      fetchEC2Instances(); // Update sheet with new states
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
               `Region: us-east-1`; // Adjust region as needed
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

function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu("EC2 Tools")
    .addItem("Refresh EC2 List", "fetchEC2Instances")
    .addItem("Setup Edit Trigger", "setupEditTrigger")
    .addItem("Setup Shift Trigger", "setupShiftTrigger")
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

// Utility to capitalize first letter (not built-in)
String.prototype.capitalize = function() {
  return this.charAt(0).toUpperCase() + this.slice(1);
};
