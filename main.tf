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

# Get the public IP of k8-master (jenkins-k8-master)
data "external" "k8_master_ip" {
  program = ["bash", "-c", "echo '{\"public_ip\": \"'$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)'\"}'"]
}

# Security group for k8-worker
resource "aws_security_group" "k8_worker_sg" {
  name        = "k8-worker-sg"
  description = "Security group for Kubernetes worker node"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSH from jenkins-k8-master
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["3.83.26.46/32"]
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
    Name = "k8-worker-sg"
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
              # Update system
              yum update -y

              # Install containerd
              yum install -y containerd
              systemctl enable containerd
              systemctl start containerd

              # Install Kubernetes components (kubeadm, kubelet, kubectl)
              cat <<EOT > /etc/yum.repos.d/kubernetes.repo
              [kubernetes]
              name=Kubernetes
              baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
              enabled=1
              gpgcheck=1
              gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
              EOT
              yum install -y kubeadm-1.29.3 kubelet-1.29.3 kubectl-1.29.3
              systemctl enable kubelet
              systemctl start kubelet

              # Disable swap (required by Kubernetes)
              swapoff -a
              sed -i '/swap/d' /etc/fstab

              # Configure sysctl for Kubernetes networking
              cat <<EOT > /etc/sysctl.d/k8s.conf
              net.bridge.bridge-nf-call-iptables  = 1
              net.bridge.bridge-nf-call-ip6tables = 1
              net.ipv4.ip_forward                 = 1
              EOT
              sysctl --system
              EOF

  tags = {
    Name = "k8-worker"
  }
}

# SSH key pair for k8-worker
resource "aws_key_pair" "k8_worker_key" {
  key_name   = "k8-worker-key"
  public_key = file("${path.module}/k8-worker-key.pub")  # Reference the key in the k8s-terraform directory
}

# Output the public IP of k8-worker
output "k8_worker_public_ip" {
  value = aws_instance.k8_worker.public_ip
}
