# Variable for the SSH public key
variable "ssh_public_key" {
  description = "The SSH public key to use for the k8-worker instance"
  type        = string
}

provider "aws" {
  region = "us-east-1"  # Replace with your region
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source to get the default subnet
data "aws_subnet" "default" {
  vpc_id = data.aws_vpc.default.id
  availability_zone = "us-east-1a"  # Replace with your AZ
}

# Security group for k8-worker
resource "aws_security_group" "k8_worker_sg" {
  name        = "k8-worker-partha-sg"
  description = "Security group for Kubernetes worker node"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSH from jenkins-k8-master
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["3.83.26.46/32"]  # Hardcoded public IP of k8-master
  }

  # Allow Kubernetes API server communication (port 6443)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Flannel CNI (port 8472/udp)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubelet (port 10250)
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8-worker-partha-sg"
  }
}

# EC2 instance for k8-worker
resource "aws_instance" "k8_worker" {
  ami                    = "ami-0a38b8c18f189761a"  # Amazon Linux 2 AMI for us-east-1 (update if needed)
  instance_type          = "t2.micro"            # 2 vCPUs, 4GB RAM
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.k8_worker_sg.id]
  key_name               = aws_key_pair.k8_worker_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              # Define log file
              LOG_FILE="/var/log/user-data.log"
              exec > >(tee -a $LOG_FILE) 2>&1
              set -x

              echo "Starting user data script at \$(date)"

              # Update system and install basic utilities
              echo "Updating system..." | tee -a $LOG_FILE
              for i in {1..5}; do
                  yum update -y && break
                  echo "Retry \$i: yum update failed, waiting 10 seconds..." | tee -a $LOG_FILE
                  sleep 10
              done

              # Install containerd as container runtime
              echo "Installing containerd..." | tee -a $LOG_FILE
              for i in {1..5}; do
                  yum install -y containerd && break
                  echo "Retry \$i: yum install containerd failed, waiting 10 seconds..." | tee -a $LOG_FILE
                  sleep 10
              done
              systemctl enable containerd
              systemctl start containerd

              # Configure containerd
              mkdir -p /etc/containerd
              containerd config default > /etc/containerd/config.toml
              sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
              systemctl restart containerd

              # Disable SELinux (simplified for learning)
              setenforce 0
              sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

              # Disable swap (Kubernetes requirement)
              swapoff -a
              sed -i '/swap/d' /etc/fstab

              # Load required kernel modules
              echo "Loading kernel modules..." | tee -a $LOG_FILE
              modprobe br_netfilter
              echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf

              # Enable IP forwarding
              echo "Enabling IP forwarding..." | tee -a $LOG_FILE
              sysctl -w net.ipv4.ip_forward=1
              echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-kubernetes.conf
              sysctl --system

              # Install Kubernetes components
              echo "Installing Kubernetes components..." | tee -a $LOG_FILE
              cat <<EOT > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOT

              for i in {1..5}; do
                  yum install -y kubelet kubeadm && break
                  echo "Retry \$i: yum install kubelet kubeadm failed, waiting 10 seconds..." | tee -a $LOG_FILE
                  sleep 10
              done

              # Verify kubeadm is installed
              if ! command -v kubeadm &> /dev/null; then
                  echo "ERROR: kubeadm installation failed" | tee -a $LOG_FILE
                  exit 1
              fi

              systemctl enable kubelet
              systemctl start kubelet

              echo "User data script completed at \$(date)" | tee -a $LOG_FILE
              EOF

  tags = {
    Name = "k8-worker-partha"
  }
}

# SSH key pair for k8-worker
resource "aws_key_pair" "k8_worker_key" {
  key_name   = "k8-worker-key-partha-1"
  public_key = var.ssh_public_key  # Use the variable instead of a file
}

# Output the public IP of k8-worker
output "k8_worker_public_ip" {
  value = aws_instance.k8_worker.public_ip
}
