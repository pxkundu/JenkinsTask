// costAnalyzer.gs


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
  if (!schedulerSheet || !shiftsSheet) {
    Logger.log("Error: EC2Scheduler or DefinedShifts sheet not found");
    return;
  }
  
  // Update EC2InstanceTypes sheet with all instance types
  updateInstanceTypesSheet(ss, schedulerSheet);
  
  // Determine the number of days in the current month (March 2025)
  const currentDate = new Date(); // March 21, 2025
  const year = currentDate.getFullYear();
  const month = currentDate.getMonth(); // 2 (March)
  const daysInMonth = new Date(year, month + 1, 0).getDate(); // 31 days
  Logger.log(`Days in current month: ${daysInMonth}`);
  
  // Automation Cost Breakdown (for EC2 API calls, assuming these are direct EC2 API calls)
  const runsPerDay = 24 * 60; // Every minute (for Start/Stop)
  const fetchCallsPerDay = 24 * 6; // Every 10 minutes (for Fetch)
  
  const fetchCallsMonthly = fetchCallsPerDay * daysInMonth;
  const startCallsMonthly = runsPerDay * daysInMonth;
  const stopCallsMonthly = runsPerDay * daysInMonth;
  
  const fetchCostDaily = fetchCallsPerDay * API_CALL_COST;
  const startCostDaily = runsPerDay * API_CALL_COST;
  const stopCostDaily = runsPerDay * API_CALL_COST;
  
  const monthlyFetchCost = fetchCostDaily * daysInMonth;
  const monthlyStartCost = startCostDaily * daysInMonth;
  const monthlyStopCost = stopCostDaily * daysInMonth;
  const totalAutomationCost = monthlyFetchCost + monthlyStartCost + monthlyStopCost;
  
  costSheet.appendRow([
    "Automation",
    "Fetch Instances",
    `${fetchCallsPerDay} daily API calls (${fetchCallsMonthly} monthly) at $${API_CALL_COST}/call`,
    monthlyFetchCost.toFixed(2)
  ]);
  costSheet.appendRow([
    "Automation",
    "Start Instances",
    `${runsPerDay} daily API calls (${startCallsMonthly} monthly) at $${API_CALL_COST}/call`,
    monthlyStartCost.toFixed(2)
  ]);
  costSheet.appendRow([
    "Automation",
    "Stop Instances",
    `${runsPerDay} daily API calls (${stopCallsMonthly} monthly) at $${API_CALL_COST}/call`,
    monthlyStopCost.toFixed(2)
  ]);
  costSheet.appendRow([
    "Automation",
    "Total",
    "Total monthly automation cost",
    totalAutomationCost.toFixed(2)
  ]);
  
  // EC2 Cost Breakdown
  const shiftData = shiftsSheet.getRange("A2:C7").getValues();
  const instanceData = schedulerSheet.getRange("A2:F" + schedulerSheet.getLastRow()).getValues();
  const instanceTypesSheet = ss.getSheetByName(INSTANCE_TYPES_SHEET);
  const instanceTypesData = instanceTypesSheet.getRange("A2:B" + instanceTypesSheet.getLastRow()).getValues();
  
  let totalEC2Cost = 0;
  instanceData.forEach(row => {
    const instanceId = row[0];
    const instanceType = row[2]; // Type is Column C (index 2)
    const shiftName = row[5]; // Shift is Column F (index 5)
    const currentState = row[3]; // Current State is Column D (index 3)
    
    if (shiftName && shiftName !== DEFAULT_SHIFT && currentState !== "terminated") {
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
        const shiftHoursPerDay = (endHour * 60 + endMin - (startHour * 60 + startMin)) / 60 || 24;
        const totalHours = shiftHoursPerDay * daysInMonth;
        
        const hourlyRate = instanceTypesData.find(typeRow => typeRow[0] === instanceType)?.[1] || 0;
        if (hourlyRate === 0) {
          Logger.log(`No pricing found for instance type ${instanceType} for ${instanceId}`);
        }
        
        const monthlyCost = totalHours * hourlyRate;
        totalEC2Cost += monthlyCost;
        
        costSheet.appendRow([
          "EC2 Instances",
          instanceId,
          `${totalHours.toFixed(1)} hours (${shiftHoursPerDay.toFixed(1)} hours/day x ${daysInMonth} days, ${shiftName}, ${instanceType})`,
          monthlyCost.toFixed(2)
        ]);
      }
    }
  });
  
  costSheet.appendRow([
    "EC2 Instances",
    "Total",
    "Total monthly EC2 cost",
    totalEC2Cost.toFixed(2)
  ]);
  
  // API Gateway REST API Cost Breakdown
  // Existing API calls (Fetch, Start, Stop)
  const existingApiCalls = fetchCallsMonthly + startCallsMonthly + stopCallsMonthly;
  
  // Additional API calls for tagging
  const tagCallsPerDay = 10; // Estimated: 10 shift updates per day
  const tagCallsMonthly = tagCallsPerDay * daysInMonth; // 10 * 31 = 310 calls
  
  // Total API calls
  const totalApiCalls = existingApiCalls + tagCallsMonthly;
  Logger.log(`Total API Gateway REST API calls for the month: ${totalApiCalls}`);
  
  // Define pricing tiers (in millions)
  const tier1Limit = 333000000; // 333 million
  const tier2Limit = 667000000; // 667 million (cumulative: 333M + 667M = 1 billion)
  const tier3Limit = 19000000000; // 19 billion (cumulative: 1B + 19B = 20 billion)
  
  const tier1Rate = 3.50; // $3.50 per million
  const tier2Rate = 2.80; // $2.80 per million
  const tier3Rate = 2.38; // $2.38 per million
  const tier4Rate = 1.51; // $1.51 per million
  
  let remainingCalls = totalApiCalls;
  let apiGatewayCost = 0;
  let descriptionParts = [];
  
  // Tier 1: First 333 million
  if (remainingCalls > 0) {
    const tier1Calls = Math.min(remainingCalls, tier1Limit);
    const tier1Cost = (tier1Calls / 1000000) * tier1Rate;
    apiGatewayCost += tier1Cost;
    descriptionParts.push(`${(tier1Calls / 1000000).toFixed(3)} million calls at $${tier1Rate}/million`);
    remainingCalls -= tier1Calls;
  }
  
  // Tier 2: Next 667 million
  if (remainingCalls > 0) {
    const tier2Calls = Math.min(remainingCalls, tier2Limit);
    const tier2Cost = (tier2Calls / 1000000) * tier2Rate;
    apiGatewayCost += tier2Cost;
    descriptionParts.push(`${(tier2Calls / 1000000).toFixed(3)} million calls at $${tier2Rate}/million`);
    remainingCalls -= tier2Calls;
  }
  
  // Tier 3: Next 19 billion
  if (remainingCalls > 0) {
    const tier3Calls = Math.min(remainingCalls, tier3Limit);
    const tier3Cost = (tier3Calls / 1000000) * tier3Rate;
    apiGatewayCost += tier3Cost;
    descriptionParts.push(`${(tier3Calls / 1000000).toFixed(3)} million calls at $${tier3Rate}/million`);
    remainingCalls -= tier3Calls;
  }
  
  // Tier 4: Over 20 billion
  if (remainingCalls > 0) {
    const tier4Calls = remainingCalls;
    const tier4Cost = (tier4Calls / 1000000) * tier4Rate;
    apiGatewayCost += tier4Cost;
    descriptionParts.push(`${(tier4Calls / 1000000).toFixed(3)} million calls at $${tier4Rate}/million`);
  }
  
  // Combine description parts
  const apiGatewayDescription = `${descriptionParts.join(" + ")} (${(totalApiCalls / 1000000).toFixed(3)} million total calls)`;
  
  costSheet.appendRow([
    "API Gateway",
    "REST API Calls",
    apiGatewayDescription,
    apiGatewayCost.toFixed(2)
  ]);
  costSheet.appendRow([
    "API Gateway",
    "Total",
    "Total monthly API Gateway cost (excl. PrivateLink charges)",
    apiGatewayCost.toFixed(2)
  ]);
  
  // Grand Total
  const grandTotal = totalAutomationCost + totalEC2Cost + apiGatewayCost;
  costSheet.appendRow([
    "Grand Total",
    "",
    "Total monthly cost",
    grandTotal.toFixed(2)
  ]);
  
  // Apply styling
  styleCostAnalysisSheet(costSheet);
}

function updateInstanceTypesSheet(ss, schedulerSheet) {
  let instanceTypesSheet = ss.getSheetByName(INSTANCE_TYPES_SHEET);
  if (!instanceTypesSheet) {
    instanceTypesSheet = ss.insertSheet(INSTANCE_TYPES_SHEET);
  }
  instanceTypesSheet.clear();
  instanceTypesSheet.appendRow(["Instance Type", "Cost per Hour ($)"]);
  
  const allInstanceTypes = Object.keys(EC2_PRICING).sort();
  const pricingData = allInstanceTypes.map(type => [type, EC2_PRICING[type]]);
  
  if (pricingData.length > 0) {
    instanceTypesSheet.getRange(2, 1, pricingData.length, 2).setValues(pricingData);
    Logger.log(`updateInstanceTypesSheet: Populated ${pricingData.length} instance types`);
  } else {
    Logger.log("updateInstanceTypesSheet: No instance types found to populate");
  }
  
  styleInstanceTypesSheet(instanceTypesSheet);
}
