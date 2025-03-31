#!/bin/bash
# Save this script to a file
cat <<'EOF' > /home/ec2-user/user_data_backup.sh
$(cat "$0")
EOF
sudo chmod +x /home/ec2-user/user_data_backup.sh

# Update system and install dependencies with sudo
sudo yum update -y
sudo yum install -y yum-utils

# Install plain Docker using yum
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install AWS CLI
sudo yum install -y awscli

# Install CloudWatch Unified Agent (no Python version conflict)
sudo yum install -y amazon-cloudwatch-agent

# Create Nginx config and index.html
sudo mkdir -p /home/ec2-user/nginx
cat <<EOF > /home/ec2-user/nginx/index.html
<!DOCTYPE html><html><body><h1>Hello from Nginx on Docker!</h1></body></html>
EOF
cat <<EOF > /home/ec2-user/nginx/nginx.conf
http {
    log_format custom '\$remote_addr - \$remote_user [\$time_local] '
                      '"\$request" \$status \$body_bytes_sent '
                      '"\$http_referer" "\$http_user_agent"';
    access_log /var/log/nginx/access.log custom;
    error_log /var/log/nginx/error.log;
    server {
        listen 80;
        location / {
            root /usr/share/nginx/html;
        }
    }
}
EOF

# Build and run Nginx container with CloudWatch logging
sudo docker run -d --name nginx-container \
  -v /home/ec2-user/nginx/index.html:/usr/share/nginx/html/index.html \
  -v /home/ec2-user/nginx/nginx.conf:/etc/nginx/nginx.conf \
  -p 80:80 \
  --log-driver=awslogs \
  --log-opt awslogs-region=us-east-1 \
  --log-opt awslogs-group=nginx-logs \
  --log-opt awslogs-create-group=true \
  nginx:latest

# Configure CloudWatch Unified Agent for system logs
cat <<EOF > /tmp/cwagent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "region": "us-east-1"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "ec2-system-logs",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/tmp/cwagent.json
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent
