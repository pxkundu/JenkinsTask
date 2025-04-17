EKS Cluster Setup and Application Deployment
This project provides two shell scripts to set up an AWS EKS (Elastic Kubernetes Service) cluster using Fargate and deploy an application accessible via an Application Load Balancer (ALB). The scripts are designed to be dynamic, prompting for all required inputs, making them reusable across different environments.

set-up-infra.sh: Creates the EKS cluster, Fargate profiles, IAM roles, and other infrastructure components.
set-up-app.sh: Deploys the AWS Load Balancer Controller and the application (e.g., the 2048 game or any containerized app).

Prerequisites
Before running the scripts, ensure you have the following:

AWS Account with permissions for:

EKS (eks:*)
IAM (iam:*)
EC2 (ec2:*)
Elastic Load Balancing (elasticloadbalancing:*)


AWS CLI installed and configured with valid credentials (aws configure).

kubectl, eksctl, and helm installed on your system. The scripts will attempt to install these if missing.

Operating System: Linux, macOS, or Windows (via WSL or Chocolatey).

Network Setup:

A VPC with at least two private subnets in different Availability Zones.
Subnets must have a route to a NAT Gateway for internet access (required for Fargate pods).


Optional: Install jq for better logging of Helm chart versions:
sudo apt-get install jq  # Linux
brew install jq          # macOS



Setup Instructions
Step 1: Clone or Download the Scripts
Download the scripts (set-up-infra.sh and set-up-app.sh) to your local machine.
Step 2: Make Scripts Executable
chmod +x set-up-infra.sh set-up-app.sh

Step 3: Run Infrastructure Setup (set-up-infra.sh)
This script sets up the EKS cluster and required infrastructure.
./set-up-infra.sh

You’ll be prompted to enter:

EKS Cluster Name (e.g., my-game-cluster): A unique name for your cluster.
AWS Region (e.g., us-east-1): The region where your cluster will be created.
VPC ID (e.g., vpc-0e13ae6de03f62cd5): The VPC where the cluster will run.
Private Subnet IDs (e.g., subnet-07b231970a5ea0a3a,subnet-066008bd872659833): Comma-separated subnet IDs (must be private).
Kubernetes Version (e.g., 1.32): The Kubernetes version for the cluster.
Application Namespace (default: game-2048): Namespace for the application.
Load Balancer Namespace (default: kube-system): Namespace for the AWS Load Balancer Controller.

Duration: ~20-30 minutes due to cluster creation.
Step 4: Run Application Deployment (set-up-app.sh)
This script deploys the AWS Load Balancer Controller and the application.
./set-up-app.sh

You’ll be prompted to enter:

EKS Cluster Name, AWS Region, VPC ID, Application Namespace, and Load Balancer Namespace: These must match the values used in Step 3.
Container Image (default: public.ecr.aws/l6m2t8p7/docker-2048:latest): The container image for your application. The default deploys the 2048 game.

Duration: ~5-15 minutes, depending on ALB provisioning.
Step 5: Access the Application
After set-up-app.sh completes, it will output the ALB URL for your application, e.g.:
Application is accessible at: http://k8s-game2048-ingress2-ff4d192d60-652303599.us-east-1.elb.amazonaws.com/ 

Open this URL in a browser to access your application.
Verification

Check the EKS Cluster:
aws eks describe-cluster --name <cluster-name> --region <region> --query 'cluster.version'


Verify the Application:
kubectl get deployment -n <app-namespace> deployment-app
kubectl get service -n <app-namespace> service-app
kubectl get ingress -n <app-namespace> ingress-app


Check the Load Balancer Controller:
kubectl get deployment -n <lb-namespace> aws-load-balancer-controller



Troubleshooting

AWS Credentials Error:
Ensure your AWS CLI is configured (aws configure) with sufficient permissions.


VPC/Subnet Issues:
Verify that the VPC and subnets exist in the specified region.
Subnets must be private (no direct route to an Internet Gateway) and have a NAT Gateway for internet access.


Ingress URL Not Available:
ALB provisioning can take several minutes. The script waits up to 15 minutes.
Check Ingress status: kubectl describe ingress -n <app-namespace> ingress-app.


Cluster Access Issues:
Ensure your kubeconfig is updated: aws eks update-kubeconfig --name <cluster-name> --region <region>.



Cleanup
If the scripts fail, they attempt to clean up created resources. For manual cleanup:
eksctl delete cluster --name <cluster-name> --region <region>
aws iam delete-policy --policy-arn arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy-<timestamp>
aws iam delete-role --role-name EKSLoadBalancerControllerRole

Notes

Custom Applications: Use a different container image in set-up-app.sh to deploy any application. Ensure the image exposes port 80.
Consistency: Use the same values for cluster name, region, VPC ID, and namespaces in both scripts.
Permissions: If you encounter AccessDenied errors, verify your AWS IAM role permissions.

For detailed logs, check the script outputs. For further assistance, refer to the AWS EKS documentation.

Happy Deploying! 🚀
Prepared by: Partha Sarathi Kundu [github/pxkundu]
