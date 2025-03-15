#!/bin/bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.medium \
  --key-name <your-key> \
  --security-group-ids <sg-id> \
  --subnet-id <subnet-id> \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=TaskManagerProd}]' \
  --iam-instance-profile Name=JenkinsSlaveRole \
  --user-data '#!/bin/bash
    yum update -y
    yum install -y docker awscli
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose'
