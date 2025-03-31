# Nginx Docker AWS Project
Deploys an EC2 instance with Docker and Nginx using a Dockerfile and setup script executed via user_data.

## Prerequisites
- AWS CLI configured with credentials.
- Existing VPC, Subnet, Security Group (with HTTP:80 inbound), and Key Pair in AWS Console.

## Project folder structure
.
├── README.md                # Project documentation (this file)
├── env/                     # Environment-specific configurations
│   ├── dev/                 # Development environment configuration
│   │   ├── main.tf          # Core Terraform configuration for dev
│   │   ├── outputs.tf       # Output definitions for dev
│   │   ├── terraform.tfvars # Variable values specific to dev
│   │   └── variables.tf     # Variable definitions for dev
│   └── stage/               # Staging environment configuration
├── files/                   # Static files and scripts used in the infrastructure
│   ├── Dockerfile           # Docker configuration file
│   ├── index.html           # Sample HTML file (e.g., for a web server)
│   ├── nginx.conf           # NGINX configuration file
│   ├── setup.sh             # Setup script for provisioning
│   └── user_data.sh         # User data script for EC2 instances
└── modules/                 # Reusable Terraform modules
    └── ec2/                 # EC2-specific module
        ├── main.tf          # EC2 resource definitions
        ├── outputs.tf       # EC2 module outputs
        └── variables.tf     # EC2 module variables

## Usage
1. Update `env/dev/terraform.tfvars` with your existing subnet_id, security_group_id, and key_name.
2. Navigate to `env/dev/` and deploy:
   ```bash
   terraform init
   terraform apply
   ```
4. Access Nginx at `http://<public-ip>`.
5. Check logs in CloudWatch (`nginx-logs`, `ec2-system-logs`) or SSH to instance (`sudo cat /var/log/user-data.log`).

## Log Groups
- `nginx-logs`: Nginx container logs (30-day retention).
- `ec2-system-logs`: System and user-data logs (30-day retention).
  - Stream `{instance_id}`: Logs from /var/log/messages.
  - Stream `{instance_id}-user-data`: Logs from /var/log/user-data.log.

## Querying Logs with CloudWatch Logs Insights
To filter logs by date-time range and keyword, use the following query in CloudWatch Logs Insights:

### Example Query
```
fields @timestamp, @message
| filter @message like /Custom/
    and @timestamp >= '2025-03-27T00:00:00Z'
    and @timestamp <= '2025-03-27T23:59:59Z'
| sort @timestamp desc
| limit 50
```

- **Steps in AWS Console**:
  1. Go to CloudWatch > Logs > Logs Insights.
  2. Select the log group (`ec2-system-logs` or `nginx-logs`).
  3. Paste the query, adjust the keyword (e.g., replace `Custom` with your search term), and set the time range.
  4. Click "Run Query".

- **Using AWS CLI**:
  ```bash
  aws logs start-query     --log-group-name "ec2-system-logs"     --start-time 1743048000     --end-time 1743134399     --query-string "fields @timestamp, @message | filter @message like /Custom/ | sort @timestamp desc | limit 50"     --region us-east-1
  aws logs get-query-results --query-id <query-id-from-previous-command> --region us-east-1
  ```
  - Replace `Custom` with your keyword and adjust dates as needed.

## Outputs
- `nginx_public_ip`: Public IP of the EC2 instance.
