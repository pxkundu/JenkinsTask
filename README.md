# Nginx Docker AWS Project
Deploys an EC2 instance with Docker and Nginx using a Dockerfile and setup script executed via user_data.

## Prerequisites
- AWS CLI configured with credentials.
- Existing VPC, Subnet, Security Group (with HTTP:80 inbound), and Key Pair in AWS Console.

## Usage
1. Update `env/dev/terraform.tfvars` with your existing subnet_id, security_group_id, and key_name.
2. Run `./generate_project.sh` to create the structure.
3. Navigate to `env/dev/` and deploy:
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
