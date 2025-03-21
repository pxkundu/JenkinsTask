// ec2Scheduler.gs

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
