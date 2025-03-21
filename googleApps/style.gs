// style.gs

// Color Constants
const HEADER_BG_COLOR = "#FFC107"; // Orange header background
const RUNNING_BG_COLOR = "#00FF00"; // Green for "running"
const STOPPED_BG_COLOR = "#FF0000"; // Red for "stopped"
const ODD_ROW_BG_COLOR = "#fce790"; // Light gray for odd rows (row 3, 5, ...)
const EVEN_ROW_BG_COLOR = "#FFFFFF"; // White for even rows (row 2, 4, ...)

function styleEC2SchedulerSheet(sheet) {
  if (!sheet) {
    Logger.log("Error: sheet is undefined in styleEC2SchedulerSheet");
    return;
  }

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();
  if (lastRow < 1 || lastColumn < 1) {
    Logger.log(`styleEC2SchedulerSheet: Sheet ${sheet.getName()} is empty, skipping styling`);
    return;
  }

  // Style Header Row
  const headerRange = sheet.getRange(1, 1, 1, lastColumn);
  headerRange
    .setBackground(HEADER_BG_COLOR)
    .setFontWeight("bold")
    .setHorizontalAlignment("center")
    .setFontColor("black");

  // Style Data Rows
  if (lastRow > 1) {
    const dataRange = sheet.getRange(2, 1, lastRow - 1, lastColumn);
    dataRange.setFontColor("black");

    // Alternating row colors
    for (let row = 2; row <= lastRow; row++) {
      const rowRange = sheet.getRange(row, 1, 1, lastColumn);
      const isOddRow = (row % 2) === 1; // Row 2 is even (white), Row 3 is odd (gray)
      rowRange.setBackground(isOddRow ? ODD_ROW_BG_COLOR : EVEN_ROW_BG_COLOR);

      // Style Current State (Column D, index 4)
      if (lastColumn >= 4) { // Ensure the column exists
        const stateCell = sheet.getRange(row, 4);
        const state = stateCell.getValue();
        switch (state) {
          case "running":
            stateCell.setBackground(RUNNING_BG_COLOR);
            break;
          case "stopped":
            stateCell.setBackground(STOPPED_BG_COLOR);
            break;
          default:
            stateCell.setBackground(isOddRow ? ODD_ROW_BG_COLOR : EVEN_ROW_BG_COLOR);
        }
      }
    }
  }

  // Add borders to the entire data range (headers + data)
  const fullRange = sheet.getRange(1, 1, lastRow, lastColumn);
  fullRange.setBorder(true, true, true, true, true, true, "black", SpreadsheetApp.BorderStyle.SOLID);

  // Auto-resize columns
  sheet.autoResizeColumns(1, lastColumn);
}

function styleDefinedShiftsSheet(sheet) {
  if (!sheet) {
    Logger.log("Error: sheet is undefined in styleDefinedShiftsSheet");
    return;
  }

  Logger.log(`Applying styling to DefinedShifts sheet: ${sheet.getName()}`);

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();
  if (lastRow < 1 || lastColumn < 1) {
    Logger.log(`styleDefinedShiftsSheet: Sheet ${sheet.getName()} is empty, skipping styling`);
    return;
  }

  // Style Header Row
  const headerRange = sheet.getRange(1, 1, 1, lastColumn);
  headerRange
    .setBackground(HEADER_BG_COLOR)
    .setFontWeight("bold")
    .setHorizontalAlignment("center")
    .setFontColor("black");

  // Style Data Rows
  if (lastRow > 1) {
    const dataRange = sheet.getRange(2, 1, lastRow - 1, lastColumn);
    dataRange.setFontColor("black");

    // Alternating row colors
    for (let row = 2; row <= lastRow; row++) {
      const rowRange = sheet.getRange(row, 1, 1, lastColumn);
      const isOddRow = (row % 2) === 1; // Row 2 is even (white), Row 3 is odd (gray)
      rowRange.setBackground(isOddRow ? ODD_ROW_BG_COLOR : EVEN_ROW_BG_COLOR);
    }
  }

  // Add borders to the entire data range (headers + data)
  const fullRange = sheet.getRange(1, 1, lastRow, lastColumn);
  fullRange.setBorder(true, true, true, true, true, true, "black", SpreadsheetApp.BorderStyle.SOLID);

  // Auto-resize columns
  sheet.autoResizeColumns(1, lastColumn);
}

function styleCostAnalysisSheet(sheet) {
  if (!sheet) {
    Logger.log("Error: sheet is undefined in styleCostAnalysisSheet");
    return;
  }

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();
  if (lastRow < 1 || lastColumn < 1) {
    Logger.log(`styleCostAnalysisSheet: Sheet ${sheet.getName()} is empty, skipping styling`);
    return;
  }

  // Style Header Row
  const headerRange = sheet.getRange(1, 1, 1, lastColumn);
  headerRange
    .setBackground(HEADER_BG_COLOR)
    .setFontWeight("bold")
    .setHorizontalAlignment("center")
    .setFontColor("black");

  // Style Data Rows
  if (lastRow > 1) {
    const dataRange = sheet.getRange(2, 1, lastRow - 1, lastColumn);
    dataRange.setFontColor("black");

    // Alternating row colors
    for (let row = 2; row <= lastRow; row++) {
      const rowRange = sheet.getRange(row, 1, 1, lastColumn);
      const isOddRow = (row % 2) === 1; // Row 2 is even (white), Row 3 is odd (gray)
      rowRange.setBackground(isOddRow ? ODD_ROW_BG_COLOR : EVEN_ROW_BG_COLOR);
    }
  }

  // Add borders to the entire data range (headers + data)
  const fullRange = sheet.getRange(1, 1, lastRow, lastColumn);
  fullRange.setBorder(true, true, true, true, true, true, "black", SpreadsheetApp.BorderStyle.SOLID);

  // Auto-resize columns
  sheet.autoResizeColumns(1, lastColumn);
}

function styleInstanceTypesSheet(sheet) {
  if (!sheet) {
    Logger.log("Error: sheet is undefined in styleInstanceTypesSheet");
    return;
  }

  Logger.log(`Applying styling to EC2InstanceTypes sheet: ${sheet.getName()}`);

  const lastRow = sheet.getLastRow();
  const lastColumn = sheet.getLastColumn();
  if (lastRow < 1 || lastColumn < 1) {
    Logger.log(`styleInstanceTypesSheet: Sheet ${sheet.getName()} is empty, skipping styling`);
    return;
  }

  // Style Header Row
  const headerRange = sheet.getRange(1, 1, 1, lastColumn);
  headerRange
    .setBackground(HEADER_BG_COLOR)
    .setFontWeight("bold")
    .setHorizontalAlignment("center")
    .setFontColor("black");

  // Style Data Rows
  if (lastRow > 1) {
    const dataRange = sheet.getRange(2, 1, lastRow - 1, lastColumn);
    dataRange.setFontColor("black");

    // Alternating row colors
    for (let row = 2; row <= lastRow; row++) {
      const rowRange = sheet.getRange(row, 1, 1, lastColumn);
      const isOddRow = (row % 2) === 1; // Row 2 is even (white), Row 3 is odd (gray)
      rowRange.setBackground(isOddRow ? ODD_ROW_BG_COLOR : EVEN_ROW_BG_COLOR);
    }
  }

  // Add borders to the entire data range (headers + data)
  const fullRange = sheet.getRange(1, 1, lastRow, lastColumn);
  fullRange.setBorder(true, true, true, true, true, true, "black", SpreadsheetApp.BorderStyle.SOLID);

  // Auto-resize columns
  sheet.autoResizeColumns(1, lastColumn);
}
