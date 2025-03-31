#!/bin/bash

# Redirect output to a log file for debugging
exec > /var/log/user-data.log 2>&1

echo "Starting setup.sh execution..."

# Update system and install dependencies
echo "Updating system and installing yum-utils..."
sudo yum update -y
sudo yum install -y yum-utils

# Install plain Docker
echo "Installing Docker..."
sudo yum install -y docker
echo "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Wait for Docker to be fully active
echo "Waiting for Docker to be active..."
timeout 60s bash -c "until sudo systemctl is-active docker; do echo 'Docker not yet active, waiting 5 seconds...'; sleep 5; done"
if [ $? -eq 0 ]; then
    echo "Docker is active."
else
    echo "Docker failed to start within 60 seconds."
    exit 1
fi

# Configure CloudWatch Unified Agent for system logs
echo "Installing and configuring CloudWatch Agent..."
sudo yum install -y awscli amazon-cloudwatch-agent
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
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "ec2-system-logs",
            "log_stream_name": "{instance_id}-user-data"
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

# Build and run the Nginx container
echo "Building Docker image..."
sudo docker build -t my-nginx-image /home/ec2-user/
if [ $? -eq 0 ]; then
    echo "Docker image built successfully."
else
    echo "Failed to build Docker image."
    exit 1
fi

echo "Running Docker container..."
sudo docker run -d --name nginx-container \
  -p 80:80 \
  --log-driver=awslogs \
  --log-opt awslogs-region=us-east-1 \
  --log-opt awslogs-group=nginx-logs \
  --log-opt awslogs-create-group=true \
  my-nginx-image
if [ $? -eq 0 ]; then
    echo "Docker container started successfully."
else
    echo "Failed to start Docker container."
    exit 1
fi


# Generate logs in /var/log/messages (for {instance_id} stream)
echo "Generating system logs in /var/log/messages..."
sudo logger "System log message #1 from setup.sh at $(date)"
sudo logger "System log message #2 from setup.sh at $(date)"
sudo systemctl restart docker # Trigger a system event
sudo echo "System log message #3 from setup.sh at $(date)" | sudo tee -a /var/log/messages


echo "setup.sh execution completed."
