// identifiers.gs

// API Endpoints
const BASE_URL = "https://9j5u6ivcja.execute-api.us-east-1.amazonaws.com/prod";
const INSTANCES_URL = `${BASE_URL}/instances`;
const START_URL = `${BASE_URL}/start`;
const STOP_URL = `${BASE_URL}/stop`;
const TAG_URL = `${BASE_URL}/tag`; // New endpoint for tagging

// Sheet Names
const SCHEDULER_SHEET = "EC2Scheduler";
const SHIFTS_SHEET = "DefinedShifts";
const COST_SHEET = "CostAnalysis";
const INSTANCE_TYPES_SHEET = "EC2InstanceTypes";

// Scheduler Constants
const DEFAULT_SHIFT = "No Shift Selected";
const SHIFT_PROPERTY_KEY = "instanceShifts";
const MANAGER_EMAIL = "partha.kundu@techconsulting.tech";

// Google Chat webhook URL (replace with your actual webhook URL)
const GOOGLE_CHAT_WEBHOOK_URL = "https://chat.googleapis.com/v1/spaces/XXXX/messages?key=YYYY&token=ZZZZ";

// Slack webhook URL (replace with your actual webhook URL)
const SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/TXXXX/BXXXX/XXXX";

// Simulated EC2_PRICING object (unchanged)
const EC2_PRICING = {
  "t2.micro": 0.0116,
  "t2.small": 0.023,
  "t3.micro": 0.0104,
  "t3.small": 0.0208,
  "t3.medium": 0.0416,
  "m5.large": 0.096,
  "m5.xlarge": 0.192,
  "m6i.large": 0.192,
  "m6i.xlarge": 0.384,
  "m6g.medium": 0.0385,
  "c5.large": 0.085,
  "c5.xlarge": 0.17,
  "c6i.large": 0.085,
  "c6g.medium": 0.034,
  "r5.large": 0.126,
  "r5.xlarge": 0.252,
  "r6i.large": 0.126,
  "r6g.medium": 0.0504,
  "i3.large": 0.156,
  "i3.xlarge": 0.312,
  "i4i.large": 0.172,
  "p3.2xlarge": 3.06,
  "g4dn.xlarge": 0.526,
  "u-6tb1.metal": 31.20
};

// Placeholder for EC2 API call cost
const API_CALL_COST = 0.0001; // $0.001 per API call

