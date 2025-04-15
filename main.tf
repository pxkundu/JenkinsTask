# Variables
variable "ssh_public_key" {
  description = "SSH public key for accessing the k8-worker instance"
  type        = string
}

# Key pair for k8-worker
resource "aws_key_pair" "k8_worker_key" {
  key_name   = "k8-worker-key"
  public_key = var.ssh_public_key
}

# Security group for k8-worker
resource "aws_security_group" "k8_worker_sg" {
  name        = "k8-worker-sg"
  description = "Security group for k8-worker instance"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["3.83.26.46/32"]  # Allow SSH from k8-master (Jenkins server)
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all traffic (adjust as needed for production)
  }

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

# k8-worker EC2 instance
resource "aws_instance" "k8_worker" {
  ami           = "ami-0a38b8c18f189761a"  # Amazon Linux 2 AMI in us-east-1
  instance_type = "t3.medium"
  key_name      = aws_key_pair.k8_worker_key.key_name
  vpc_security_group_ids = [aws_security_group.k8_worker_sg.id]

  tags = {
    Name = "k8-worker-partha"
  }
}

# Output the public IP of k8-worker
output "k8_worker_public_ip" {
  value = aws_instance.k8_worker.public_ip
}
