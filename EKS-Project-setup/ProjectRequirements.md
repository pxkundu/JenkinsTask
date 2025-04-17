EKS Cluster Setup and Application Deployment: Prerequisites and Assumptions
This project provides two shell scripts to set up an AWS EKS (Elastic Kubernetes Service) cluster using Fargate and deploy an application accessible via an Application Load Balancer (ALB). Before running the scripts, ensure that all prerequisites are met and assumptions are understood to avoid runtime issues.

set-up-infra.sh: Creates the EKS cluster, Fargate profiles, IAM roles, and other infrastructure components.
set-up-app.sh: Deploys the AWS Load Balancer Controller and the application (default: 2048 game).

Prerequisites
Ensure the following requirements are met before running the scripts:
1. AWS Account and Permissions

AWS Account: You must have an active AWS account.
IAM Permissions: The AWS user or role used to run the scripts must have permissions for the following services:
EKS: Full access to manage clusters (eks:*).
IAM: Ability to create and manage roles, policies, and service accounts (iam:*).
EC2: Permissions to manage VPCs, subnets, security groups, and route tables (ec2:*).
Elastic Load Balancing: Permissions to create and manage ALBs (elasticloadbalancing:*).
CloudFormation: Permissions to create stacks (used by eksctl for IAM service accounts) (cloudformation:*).
Example IAM policy:{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*",
                "iam:*",
                "ec2:*",
                "elasticloadbalancing:*",
                "cloudformation:*"
            ],
            "Resource": "*"
        }
    ]
}




AWS CLI: Installed and configured with valid credentials.
Install AWS CLI: AWS CLI Installation Guide.
Configure credentials: Run aws configure and provide your Access Key ID, Secret Access Key, default region, and output format.



2. Network Requirements

VPC: A VPC must exist in the target region with the following:
At least two private subnets in different Availability Zones (AZs) for high availability.
Private subnets must not have a direct route to an Internet Gateway (IGW). They should route outbound traffic through a NAT Gateway.
Example setup:
VPC: vpc-0e13ae6de03f62cd5
Private Subnets: subnet-07b231970a5ea0a3a (us-east-1a), subnet-066008bd872659833 (us-east-1b)




NAT Gateway: Required for Fargate pods to access the internet (e.g., to pull container images).
Ensure a NAT Gateway exists in a public subnet, and the private subnets’ route tables point to it for 0.0.0.0/0 traffic.


DNS Resolution: The VPC must have DNS hostnames and DNS resolution enabled (enableDnsHostnames and enableDnsSupport set to true).
Check and enable using AWS CLI:aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsHostnames --region <region>
aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsSupport --region <region>
aws ec2 modify-vpc-attribute --vpc-id <vpc-id> --enable-dns-hostnames --region <region>
aws ec2 modify-vpc-attribute --vpc-id <vpc-id> --enable-dns-support --region <region>




How to Verify:
List VPCs: aws ec2 describe-vpcs --region <region>
List Subnets: aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc-id> --region <region>
Check Route Tables: aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<subnet-id> --region <region>



3. Tools and Dependencies

Operating System: The scripts are compatible with:
Linux (e.g., Ubuntu, CentOS)
macOS
Windows (via WSL or Chocolatey)


Required Tools:
AWS CLI: Must be installed and configured (see above).
kubectl: Kubernetes command-line tool to interact with the cluster.
eksctl: Tool to manage EKS clusters.
helm: Package manager for Kubernetes to install the AWS Load Balancer Controller.


Optional Tool:
jq: For parsing JSON output to log Helm chart versions. If not installed, the script will log a warning but continue.
Install on Linux: sudo apt-get install jq
Install on macOS: brew install jq
Install on Windows (Chocolatey): choco install jq




Automatic Installation: If kubectl, eksctl, or helm are missing, the script will attempt to install them. However, it’s recommended to install them manually to ensure compatibility:
kubectl: Install kubectl
eksctl: Install eksctl
helm: Install Helm



4. Internet Access

The machine running the scripts must have internet access to:
Download tools (kubectl, eksctl, helm) if not already installed.
Pull container images (e.g., the default 2048 game image: public.ecr.aws/l6m2t8p7/docker-2048:latest).
Communicate with AWS APIs.



5. Disk Space and Memory

Ensure the machine has sufficient disk space and memory:
Disk Space: At least 1 GB free for downloading tools and temporary files.
Memory: At least 2 GB of free memory for running the scripts and tools.



Assumptions
The scripts make the following assumptions about your environment and setup:
1. AWS Credentials Are Valid

The scripts assume that aws sts get-caller-identity succeeds, indicating valid AWS credentials.
If credentials are invalid or expired, the scripts will fail with an error.

2. AWS Region Support

The scripts assume the specified AWS region supports EKS and Fargate.
Not all regions support EKS or Fargate (e.g., some newer regions might not). Common regions like us-east-1, us-west-2, and eu-west-1 are generally safe choices.
The scripts validate the region using aws ec2 describe-regions.

3. Kubernetes Version Support

The scripts assume the specified Kubernetes version is supported by EKS in the chosen region.
As of April 2025, supported versions are typically in the range of 1.24 to 1.32 (check with aws eks describe-eks-versions --region <region>).
The scripts validate the version using aws eks describe-addon-versions.

4. Network Configuration

Private Subnets: The scripts assume the provided subnets are private (no direct route to an Internet Gateway) and have a NAT Gateway for outbound internet access.
Subnet Availability Zones: At least two subnets in different AZs are assumed for high availability. The script will warn if this condition isn’t met but will continue.
VPC DNS Settings: The VPC must have DNS hostnames and resolution enabled (assumption aligns with AWS best practices for EKS).

5. Container Image

The application deployment script (set-up-app.sh) assumes the container image exposes port 80, as the Kubernetes manifest is configured to use this port.
Default image: public.ecr.aws/l6m2t8p7/docker-2048:latest (the 2048 game). If using a custom image, ensure it exposes port 80 or modify the manifest in the script.

6. Script Execution Environment

The scripts assume they are run in a Bash-compatible shell (e.g., Bash on Linux/macOS, WSL on Windows).
They assume the user has appropriate permissions to execute shell commands (e.g., sudo for installing tools if required).

7. Idempotency and Cleanup

The scripts assume they can safely delete and recreate resources (e.g., IAM roles, Fargate profiles) if they already exist.
If a script fails, it attempts to clean up created resources. However, manual cleanup may be required if the script is interrupted (e.g., via Ctrl+C).

Pre-Run Checklist
Before running the scripts, verify the following:

AWS Credentials:

Run aws sts get-caller-identity to confirm your credentials are valid.
Check your IAM permissions to ensure they include the required actions.


Network Setup:

Confirm your VPC and subnets exist: aws ec2 describe-vpcs --region <region> and aws ec2 describe-subnets --region <region>.
Verify subnets are private and have a NAT Gateway route.
Ensure DNS settings are enabled for the VPC.


Tools:

Check if tools are installed:aws --version
kubectl version --client
eksctl version
helm version


Install any missing tools manually or let the script handle it.


Kubernetes Version:

Verify the desired Kubernetes version is supported:aws eks describe-eks-versions --region <region>




Internet Access:

Test connectivity: ping google.com.



Running the Scripts
After ensuring all prerequisites and assumptions are met:

Make Scripts Executable:
chmod +x set-up-infra.sh set-up-app.sh


Run Infrastructure Setup:
./set-up-infra.sh


Follow the prompts to provide cluster name, region, VPC ID, subnet IDs, Kubernetes version, and namespaces.


Run Application Deployment:
./set-up-app.sh


Provide the same values as in the first script, plus the container image for the application.



Post-Run Verification

Cluster Status:aws eks describe-cluster --name <cluster-name> --region <region>


Application Status:kubectl get deployment -n <app-namespace> deployment-app
kubectl get ingress -n <app-namespace> ingress-app



Troubleshooting

AWS Permission Errors:
Check your IAM role permissions and ensure they include the required actions.


Network Issues:
Verify subnet routing and NAT Gateway setup.


Tool Installation Failures:
Install tools manually if the script fails to do so.


Manual Cleanup (if needed):eksctl delete cluster --name <cluster-name> --region <region>
aws iam delete-policy --policy-arn arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy-<timestamp>
aws iam delete-role --role-name EKSLoadBalancerControllerRole


Prepared by: Partha Sarathi Kundu [github/pxkundu]
This README ensures you’re fully prepared to run the scripts successfully. Proceed with confidence! 🚀

