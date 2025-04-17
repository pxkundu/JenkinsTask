Creating a Jenkins Pipeline with Terraform to Provision an Amazon Linux 2023 EC2 Worker Node and Join a Kubernetes Cluster
This guide provides a detailed, step-by-step process to create a Jenkins pipeline that uses Terraform to provision a t2.micro EC2 instance running Amazon Linux 2023 as a Kubernetes (K8s) worker node. The worker node will join an existing Kubernetes cluster, where the Jenkins master and Kubernetes control plane are running on the same t2.medium EC2 instance. The instructions are simplified yet comprehensive, ensuring anyone can follow along without errors or confusion.
Prerequisites
Before starting, ensure you have the following:

AWS Account:

Active AWS account with administrative access.
IAM user with programmatic access (Access Key ID and Secret Access Key).
Permissions for EC2, IAM, and EKS services.


Existing EC2 Instance:

A t2.medium EC2 instance running Amazon Linux 2023.
Preconfigured Jenkins master installed.
Kubernetes control plane running (using kubeadm for a self-managed cluster).
Access to the Kubernetes kubeconfig file and the kubeadm join command.


Tools Installed on the t2.medium Instance:

Jenkins: Accessible via http://<ec2-public-ip>:8080.
Terraform: Version 1.5.0 or later.
AWS CLI: Configured with your AWS credentials (aws configure).
kubectl: For interacting with the Kubernetes cluster.
Git: For version control.


GitHub Repository:

A repository to store Terraform scripts and the Jenkinsfile.
Personal Access Token for Jenkins to access the repository.


SSH Key Pair:

An AWS EC2 key pair for accessing the worker node (e.g., my-key-pair).


Basic Knowledge:

Familiarity with AWS, Terraform, Jenkins, and Kubernetes.
Understanding of Infrastructure as Code (IaC) and CI/CD pipelines.



Architecture Overview

Existing Setup:

A t2.medium EC2 instance hosts both the Jenkins master and the Kubernetes control plane.
The Kubernetes cluster is initialized using kubeadm.


Pipeline:

Jenkins automates the deployment process.
Pulls Terraform scripts from a GitHub repository.
Provisions a t2.micro EC2 instance (Amazon Linux 2023) as a Kubernetes worker node.
Uses user_data to install containerd, kubelet, kubeadm, and kubectl.
Joins the worker node to the existing Kubernetes cluster.


Worker Node:

Runs Amazon Linux 2023.
Configured with necessary Kubernetes packages.
Joins the cluster using a kubeadm join command.



Step-by-Step Guide
Step 1: Verify the Existing Setup

Access the t2.medium Instance:

SSH into the t2.medium EC2 instance:
ssh -i my-key-pair.pem ec2-user@<t2-medium-public-ip>




Confirm Jenkins is Running:

Check Jenkins status:
sudo systemctl status jenkins


Access Jenkins at http://<t2-medium-public-ip>:8080. Log in with your admin credentials.



Verify Kubernetes Control Plane:

Confirm the Kubernetes control plane is running:
kubectl get nodes


You should see the t2.medium instance as the control plane node (e.g., ip-<internal-ip>).



Generate kubeadm Join Command:

On the t2.medium instance, generate the join command for worker nodes:
kubeadm token create --print-join-command


Example output:
kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>


Save this command securely; it will be used in the Terraform user_data script.



Ensure Terraform is Installed:

Check Terraform version:
terraform --version


If not installed, install it:
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/terraform.repo
sudo yum install -y terraform
terraform --version




Configure AWS CLI:

Run:
aws configure


Enter your Access Key ID, Secret Access Key, region (e.g., us-east-1), and output format (json).




Step 2: Configure Jenkins

Install Required Plugins:

In Jenkins, go to Manage Jenkins > Manage Plugins > Available.
Install:
Git Plugin (for GitHub integration).
CloudBees AWS Credentials Plugin (for AWS credentials).
Pipeline Plugin (for pipeline support).




Store AWS Credentials:

Go to Manage Jenkins > Manage Credentials > System > Global Credentials > Add Credentials.
Select Kind: AWS Credentials.
Enter the Access Key ID and Secret Access Key.
Set ID to AWS_CREDENTIALS and save.


Store GitHub Credentials:

Add credentials for GitHub:
Select Kind: Username with password.
Enter your GitHub username and Personal Access Token.
Set ID to GITHUB_CREDENTIALS and save.





Step 3: Create Terraform Scripts

Create a GitHub Repository:

Create a new repository (e.g., jenkins-terraform-k8s-worker).

Clone it locally or on the t2.medium instance:
git clone https://github.com/<your-username>/jenkins-terraform-k8s-worker.git
cd jenkins-terraform-k8s-worker




Write Terraform Configuration:

Create the following files in the repository.

provider.tf:
provider "aws" {
  region = var.aws_region
}

variables.tf:
variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  default     = "my-key-pair"
}

main.tf:
# Security Group
resource "aws_security_group" "k8s_worker_sg" {
  name        = "k8s-worker-sg"
  description = "Security group for Kubernetes worker node"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-worker-sg"
  }
}

# EC2 Instance
resource "aws_instance" "k8s_worker" {
  ami                    = "ami-0c55b159cbfafe1f0" # Amazon Linux 2023 AMI (us-east-1)
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_worker_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y

              # Install containerd
              yum install -y containerd
              mkdir -p /etc/containerd
              containerd config default > /etc/containerd/config.toml
              sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
              systemctl enable containerd
              systemctl start containerd

              # Install Kubernetes components
              cat <<EOK > /etc/yum.repos.d/kubernetes.repo
              [kubernetes]
              name=Kubernetes
              baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
              enabled=1
              gpgcheck=1
              gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
              EOK

              yum install -y kubelet-1.28.0 kubeadm-1.28.0 kubectl-1.28.0
              systemctl enable kubelet
              systemctl start kubelet

              # Join Kubernetes cluster
              <your-kubeadm-join-command>
              EOF

  tags = {
    Name = "k8s-worker"
  }
}

outputs.tf:
output "worker_public_ip" {
  description = "Public IP of the worker node"
  value       = aws_instance.k8s_worker.public_ip
}


Update the Join Command:

Replace <your-kubeadm-join-command> in main.tf with the actual kubeadm join command from Step 1.4.

Example:
kubeadm join 172.31.10.10:6443 --token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:1234...abcd




Verify SSH Key Pair:

Ensure the my-key-pair exists in AWS EC2 > Key Pairs.
If not, create it in the AWS Console and download the .pem file.


Push to GitHub:

Commit and push the files:
git add .
git commit -m "Add Terraform scripts for K8s worker node"
git push origin main





Step 4: Create the Jenkins Pipeline

Create a Jenkinsfile:

In the same GitHub repository, create a Jenkinsfile:

pipeline {
    agent any
    environment {
        AWS_ACCESS_KEY_ID     = credentials('AWS_CREDENTIALS')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_CREDENTIALS')
        AWS_DEFAULT_REGION    = 'us-east-1'
    }
    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Terraform action to perform')
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }
        stage('Terraform Plan') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }
        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                sh 'terraform apply -auto-approve tfplan'
            }
        }
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                sh 'terraform destroy -auto-approve'
            }
        }
    }
    post {
        always {
            cleanWs()
        }
    }
}


Push the Jenkinsfile:
git add Jenkinsfile
git commit -m "Add Jenkinsfile for pipeline"
git push origin main



Step 5: Configure the Jenkins Pipeline

Create a New Pipeline:

In Jenkins, go to Dashboard > New Item.
Enter a name (e.g., K8s-Worker-Pipeline), select Pipeline, and click OK.


Configure the Pipeline:

In the pipeline configuration:
Definition: Select Pipeline script from SCM.
SCM: Select Git.
Repository URL: Enter https://github.com/<your-username>/jenkins-terraform-k8s-worker.git.
Credentials: Select GITHUB_CREDENTIALS.
Branch Specifier: */main.
Save the configuration.





Step 6: Run the Pipeline

Trigger the Pipeline:

Go to the pipeline in Jenkins and click Build with Parameters.
Select apply as the ACTION and click Build.


Monitor the Pipeline:

View the pipeline stages in the Jenkins UI.
Check the Console Output for Terraform logs.
The pipeline will:
Clone the repository.
Initialize Terraform.
Generate and apply the Terraform plan to create the t2.micro EC2 instance.




Verify the EC2 Instance:

In AWS Console > EC2 > Instances, confirm the k8s-worker instance is running.
Note the public IP from the Terraform output (worker_public_ip).


Verify Kubernetes Node:

On the t2.medium instance:
kubectl get nodes


Confirm the new t2.micro instance appears as a worker node (e.g., ip-<internal-ip>).




Step 7: Clean Up

Destroy Resources:

In Jenkins, run the pipeline again with ACTION set to destroy.
This will terminate the t2.micro EC2 instance and security group.


Verify Deletion:

In AWS Console, ensure the k8s-worker instance and k8s-worker-sg security group are deleted.



Troubleshooting

Pipeline Fails at Terraform Init:

Ensure Terraform is installed on the t2.medium instance.
Verify AWS credentials are correctly set in Jenkins.


Worker Node Not Joining Cluster:

Check the user_data script logs on the worker node:
ssh -i my-key-pair.pem ec2-user@<worker-public-ip>
sudo cat /var/log/cloud-init-output.log


Verify the kubeadm join command is correct.

Ensure the security group allows traffic on port 6443.



Permission Errors:

Confirm the IAM user has permissions for EC2 and IAM.
Check AWS CLI configuration on the t2.medium instance.


Jenkins Cannot Access GitHub:

Verify GitHub credentials in Jenkins.
Ensure the repository URL is correct.



Best Practices

Secure Credentials:

Use Jenkins credentials to manage AWS and GitHub secrets.
Avoid hardcoding sensitive data in Terraform files.


State Management:

Store Terraform state in an S3 bucket:
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "k8s-worker/terraform.tfstate"
    region = "us-east-1"
  }
}


Create the S3 bucket beforehand and update main.tf.



Minimal Resources:

Use t2.micro for cost efficiency in testing.
Limit security group rules to necessary ports (e.g., 22, 6443, 10250).


Logging:

Monitor user_data execution logs in /var/log/cloud-init-output.log on the worker node.



References

Terraform AWS Provider
Jenkins Pipeline Documentation
Kubernetes kubeadm
Amazon Linux 2023

Prepared by

Partha Sarathi Kundu [github/pxkundu]
