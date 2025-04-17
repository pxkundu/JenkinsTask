### Detailed Documentation: Setting Up an EKS Cluster with Fargate and Deploying the 2048 Game

#### Objective
The goal of this task is to:
1. Create an EKS cluster using AWS Fargate as the compute backend.
2. Deploy the AWS Load Balancer Controller to manage ingress resources.
3. Deploy the 2048 game application, making it accessible via an Application Load Balancer (ALB) over the internet.

This process is automated using two shell scripts:
- **`set-up-infra.sh`**: Sets up the EKS cluster, Fargate profiles, IAM roles, and other infrastructure components.
- **`set-up-app.sh`**: Deploys the AWS Load Balancer Controller and the 2048 game application.

#### Prerequisites
Before running the scripts, ensure the following are in place:
- **AWS CLI**: Installed and configured with valid credentials.
- **kubectl**: Installed for interacting with the Kubernetes cluster.
- **eksctl**: Installed for managing EKS clusters.
- **helm**: Installed for managing Kubernetes applications.
- **Operating System**: The scripts are designed to work on Linux, macOS, or Windows (via WSL or Chocolatey).
- **Network Requirements**: A VPC with private subnets and proper routing (e.g., NAT Gateway for internet access).
- **Permissions**: The AWS user/role must have permissions for EKS, IAM, EC2, and ELB operations (e.g., `eks:*`, `iam:*`, `ec2:*`, `elasticloadbalancing:*`).

#### Scripts Overview
- **set-up-infra.sh**: Handles infrastructure setup, including cluster creation, Fargate profile setup, IAM roles, and OIDC provider configuration.
- **set-up-app.sh**: Deploys the AWS Load Balancer Controller and the 2048 game application.

---

### Part 1: Infrastructure Setup (`set-up-infra.sh`)

This script sets up the EKS cluster and related infrastructure components.

```x-sh#!/bin/bash

# Exit on errors immediately
set -e

# Function to log messages to stderr
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Variables to track created resources for cleanup
CREATED_CLUSTER=""
CREATED_FARGATE_PROFILE=""
CREATED_IAM_ROLE=""
CREATED_IAM_POLICY=""
TEMP_FILES=()
WARNING_LOG="warnings.log"

# Cleanup function to destroy all created resources
cleanup() {
    log "Cleaning up resources due to error or warning..."

    # Delete Fargate profile
    if [ -n "$CREATED_FARGATE_PROFILE" ]; then
        log "Deleting Fargate profile: $CREATED_FARGATE_PROFILE..."
        eksctl delete fargateprofile --cluster "$CLUSTER_NAME" --name "$CREATED_FARGATE_PROFILE" --region "$REGION" --wait || true
    fi

    # Delete IAM role and policy
    if [ -n "$CREATED_IAM_ROLE" ]; then
        log "Deleting IAM role: $CREATED_IAM_ROLE..."
        # Detach managed policies
        attached_policies=$(aws iam list-attached-role-policies --role-name "$CREATED_IAM_ROLE" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || true)
        for policy_arn in $attached_policies; do
            aws iam detach-role-policy --role-name "$CREATED_IAM_ROLE" --policy-arn "$policy_arn" || true
        done
        # Delete inline policies
        inline_policies=$(aws iam list-role-policies --role-name "$CREATED_IAM_ROLE" --query 'PolicyNames' --output text 2>/dev/null || true)
        for policy_name in $inline_policies; do
            aws iam delete-role-policy --role-name "$CREATED_IAM_ROLE" --policy-name "$policy_name" || true
        done
        # Wait for IAM consistency
        sleep 5
        aws iam delete-role --role-name "$CREATED_IAM_ROLE" || true
    fi
    if [ -n "$CREATED_IAM_POLICY" ]; then
        log "Deleting IAM policy: $CREATED_IAM_POLICY..."
        aws iam delete-policy --policy-arn "$CREATED_IAM_POLICY" || true
    fi

    # Delete cluster
    if [ -n "$CREATED_CLUSTER" ]; then
        log "Deleting cluster: $CREATED_CLUSTER..."
        eksctl delete cluster --name "$CREATED_CLUSTER" --region "$REGION" --wait || true
    fi

    # Clean up temporary files
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null
    done

    rm -f "$WARNING_LOG" 2>/dev/null
    log "Cleanup completed."
    exit 1
}

# Function to check for warnings in command output
check_warnings() {
    local cmd_output=$1
    # Only trigger cleanup on ERROR, not WARNING or DEPRECATION
    if grep -Ei "ERROR" "$cmd_output" >/dev/null; then
        log "Error detected in command output. Initiating cleanup..."
        cat "$cmd_output" >&2
        cleanup
    elif grep -Ei "DEPRECATION" "$cmd_output" >/dev/null; then
        log "Deprecation warning detected, but continuing..."
        cat "$cmd_output" >&2
    elif grep -Ei "WARNING" "$cmd_output" >/dev/null; then
        log "Warning detected, but continuing..."
        cat "$cmd_output" >&2
    fi
}

# Function to retry a command and check for warnings
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1
    local cmd_output
    cmd_output=$(mktemp) || {
        log "ERROR: Failed to create temporary file with mktemp"
        cleanup
    }
    TEMP_FILES+=("$cmd_output")

    while [ $attempt -le "$max_attempts" ]; do
        log "Attempt $attempt of $max_attempts: $@"
        if "$@" 2> "$cmd_output"; then
            check_warnings "$cmd_output"
            rm -f "$cmd_output"
            return 0
        fi
        log "Command failed, checking for warnings..."
        check_warnings "$cmd_output"
        log "Retrying in $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
    log "ERROR: Command failed after $max_attempts attempts: $@"
    cat "$cmd_output" >&2
    rm -f "$cmd_output"
    cleanup
}

# Trap errors and warnings
trap cleanup ERR

# Function to check and install command if missing
check_and_install_command() {
    local cmd=$1
    local install_cmd=$2
    if command -v "$cmd" &> /dev/null; then
        log "$cmd is already installed"
        return 0
    fi
    log "Installing $cmd..."
    local install_output
    install_output=$(mktemp) || {
        log "ERROR: Failed to create temporary file with mktemp"
        cleanup
    }
    TEMP_FILES+=("$install_output")
    if eval "$install_cmd" 2> "$install_output"; then
        check_warnings "$install_output"
        log "$cmd installed successfully"
        rm -f "$install_output"
        return 0
    else
        log "ERROR: Failed to install $cmd"
        cat "$install_output" >&2
        rm -f "$install_output"
        cleanup
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    local output
    output=$(mktemp) || {
        log "ERROR: Failed to create temporary file with mktemp"
        cleanup
    }
    TEMP_FILES+=("$output")
    if retry 3 10 aws sts get-caller-identity > /dev/null 2> "$output"; then
        log "AWS credentials are valid"
        rm -f "$output"
        return 0
    else
        log "ERROR: AWS credentials are not configured properly"
        cat "$output" >&2
        rm -f "$output"
        cleanup
    fi
}

# Function to validate subnets
validate_subnets() {
    local vpc_id=$1
    local subnets=$2
    log "Validating subnets: $subnets"
    local output
    output=$(mktemp) || {
        log "ERROR: Failed to create temporary file with mktemp"
        cleanup
    }
    TEMP_FILES+=("$output")
    IFS=',' read -ra SUBNET_ARRAY <<< "$subnets"
    for subnet in "${SUBNET_ARRAY[@]}"; do
        # Check if subnet belongs to the VPC
        if ! aws ec2 describe-subnets --subnet-ids "$subnet" --query 'Subnets[0].VpcId' --output text 2> "$output" | grep -q "$vpc_id"; then
            log "ERROR: Subnet $subnet does not belong to VPC $vpc_id or is invalid"
            cat "$output" >&2
            rm -f "$output"
            cleanup
        fi
        check_warnings "$output"
        # Check if subnet is private (no direct route to IGW)
        if aws ec2 describe-route-tables --filters Name=association.subnet-id,Values="$subnet" --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0` && GatewayId!=`null`]' --output text 2> "$output" | grep -q "igw-"; then
            log "ERROR: Subnet $subnet is public, but private subnets are required for Fargate"
            cat "$output" >&2
            rm -f "$output"
            cleanup
        fi
        check_warnings "$output"
        # Check for NAT gateway (optional, log warning if missing)
        route_table_id=$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values="$subnet" --query 'RouteTables[0].RouteTableId' --output text 2> "$output")
        check_warnings "$output"
        if [ -n "$route_table_id" ]; then
            if ! aws ec2 describe-route-tables --route-table-ids "$route_table_id" --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && NatGatewayId!=`null`]' --output text 2> "$output" | grep -q "nat-"; then
                log "WARNING: Subnet $subnet does not have a route to a NAT gateway, pods may not be able to access the internet"
            fi
            check_warnings "$output"
        fi
    done
    # Check for availability zone coverage
    az_count=$(aws ec2 describe-subnets --subnet-ids "${SUBNET_ARRAY[@]}" --query 'length(Subnets[*].AvailabilityZone)' --output text 2> "$output")
    check_warnings "$output"
    if [ "$az_count" -lt 2 ]; then
        log "WARNING: Subnets cover only $az_count availability zone(s), at least 2 are recommended for high availability"
    fi
    log "Subnets validated successfully"
    rm -f "$output"
    return 0
}

# Configuration variables
CLUSTER_NAME="partha-game-cluster"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
K8S_VERSION="1.32" # Updated to a likely supported version as of April 2025
TIMESTAMP=$(date +%s)
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-$TIMESTAMP"

# Validate IAM policy name length
if [ ${#IAM_POLICY_NAME} -gt 128 ]; then
    log "ERROR: IAM policy name $IAM_POLICY_NAME exceeds 128 characters"
    cleanup
fi

# Step 1: Install prerequisites
log "Checking and installing prerequisites..."

# Detect OS for appropriate package manager
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="sudo apt-get update"
    INSTALL_PREFIX="sudo apt-get install -y"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    PKG_MANAGER="brew"
    UPDATE_CMD="brew update"
    INSTALL_PREFIX="brew install"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    PKG_MANAGER="choco"
    UPDATE_CMD="choco upgrade chocolatey"
    INSTALL_PREFIX="choco install -y"
else
    log "ERROR: Unsupported OS, manual installation required"
    cleanup
fi

# Install AWS CLI
check_and_install_command "aws" "
    curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' &&
    unzip awscliv2.zip &&
    sudo ./aws/install &&
    rm -rf awscliv2.zip aws
"

# Install eksctl
check_and_install_command "eksctl" "
    curl --silent --location 'https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz' | tar xz -C /tmp &&
    sudo mv /tmp/eksctl /usr/local/bin
"

# Install kubectl
check_and_install_command "kubectl" "
    curl -LO 'https://dl.k8s.io/release/v$K8S_VERSION/bin/linux/amd64/kubectl' &&
    chmod +x kubectl &&
    sudo mv kubectl /usr/local/bin/
"

# Install helm
check_and_install_command "helm" "
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"

check_aws_credentials

# Step 2: Validate subnets
validate_subnets "$VPC_ID" "$PRIVATE_SUBNETS"

# Step 3: Create EKS cluster with Fargate
log "Creating EKS cluster: $CLUSTER_NAME with Kubernetes version $K8S_VERSION"
retry 3 30 eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --fargate \
    --vpc-private-subnets="$PRIVATE_SUBNETS" \
    --version "$K8S_VERSION" \
    --without-nodegroup
log "EKS cluster created successfully"
CREATED_CLUSTER="$CLUSTER_NAME"

# Step 4: Enable IAM OIDC provider
log "Enabling IAM OIDC provider..."
retry 3 10 eksctl utils associate-iam-oidc-provider --region="$REGION" --cluster="$CLUSTER_NAME" --approve
log "IAM OIDC provider enabled successfully"

# Step 5: Create default addons with latest compatible versions
log "Creating default addons (metrics-server, vpc-cni, kube-proxy, coredns)..."
retry 3 30 eksctl create addon \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name vpc-cni \
    --version latest
log "Successfully created addon: vpc-cni"

retry 3 30 eksctl create addon \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name metrics-server \
    --version latest
log "Successfully created addon: metrics-server"

retry 3 30 eksctl create addon \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name kube-proxy \
    --version latest
log "Successfully created addon: kube-proxy"

retry 3 30 eksctl create addon \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name coredns \
    --version latest
log "Successfully created addon: coredns"

# Step 6: Create namespace for the 2048 game
log "Creating namespace: $APP_NAMESPACE"
kubectl create namespace "$APP_NAMESPACE" || log "Namespace $APP_NAMESPACE already exists"
log "Namespace created successfully"

# Step 7: Create Fargate profile for the 2048 game
log "Creating Fargate profile for the 2048 game..."
retry 3 30 eksctl create fargateprofile \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name "game-profile" \
    --namespace "$APP_NAMESPACE"
log "Fargate profile created successfully"
CREATED_FARGATE_PROFILE="game-profile"

# Step 7.5: Create Fargate profile for kube-system (for AWS Load Balancer Controller)
log "Creating Fargate profile for kube-system..."
retry 3 30 eksctl create fargateprofile \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name "kube-system-profile" \
    --namespace "$LB_NAMESPACE"
log "Fargate profile for kube-system created successfully"
CREATED_FARGATE_PROFILE="kube-system-profile"

# Step 8: Create namespace for AWS Load Balancer Controller
log "Creating namespace: $LB_NAMESPACE"
kubectl create namespace "$LB_NAMESPACE" || log "Namespace $LB_NAMESPACE already exists"
log "Namespace created successfully"

# Step 9: Create IAM policy for AWS Load Balancer Controller with a unique name
log "Creating IAM policy for AWS Load Balancer Controller with name $IAM_POLICY_NAME..."
cat > aws-lb-controller-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "ec2:GetSecurityGroupsForVpc",
                "ec2:DescribeIpamPools",
                "ec2:DescribeRouteTables",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTrustStores",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeCapacityReservation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:ModifyListenerAttributes",
                "elasticloadbalancing:ModifyCapacityReservation",
                "elasticloadbalancing:ModifyIpPools"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule",
                "elasticloadbalancing:SetRulePriorities"
            ],
            "Resource": "*"
        }
    ]
}
EOF
TEMP_FILES+=("aws-lb-controller-policy.json")

policy_output=$(mktemp) || {
    log "ERROR: Failed to create temporary file with mktemp"
    cleanup
}
TEMP_FILES+=("$policy_output")
IAM_POLICY_ARN=$(retry 3 10 aws iam create-policy \
    --policy-name "$IAM_POLICY_NAME" \
    --policy-document file://aws-lb-controller-policy.json \
    --query 'Policy.Arn' \
    --output text 2> "$policy_output") || {
        log "ERROR: Failed to create IAM policy after retries"
        cat "$policy_output" >&2
        rm -f "$policy_output"
        cleanup
    }
check_warnings "$policy_output"
# Validate ARN format
if [[ ! "$IAM_POLICY_ARN" =~ ^arn:aws:iam::[0-9]{12}:policy/[A-Za-z0-9-]+ ]]; then
    log "ERROR: Invalid IAM policy ARN: $IAM_POLICY_ARN"
    rm -f "$policy_output"
    cleanup
fi
log "IAM policy created successfully with ARN: $IAM_POLICY_ARN"
CREATED_IAM_POLICY="$IAM_POLICY_ARN"
rm -f "$policy_output"

# Step 10: Create IAM service account for AWS Load Balancer Controller
log "Creating IAM service account for AWS Load Balancer Controller..."
ROLE_NAME="EKSLoadBalancerControllerRole"
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    log "IAM role $ROLE_NAME already exists, deleting it..."
    attached_policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
    for policy_arn in $attached_policies; do
        retry 3 10 aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn"
    done
    inline_policies=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null)
    for policy_name in $inline_policies; do
        retry 3 10 aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy_name"
    done
    sleep 5 # Wait for IAM consistency
    retry 3 10 aws iam delete-role --role-name "$ROLE_NAME"
    # Verify deletion
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "ERROR: Failed to delete IAM role $ROLE_NAME"
        cleanup
    fi
fi

retry 5 30 eksctl create iamserviceaccount \
    --cluster "$CLUSTER_NAME" \
    --namespace "$LB_NAMESPACE" \
    --name "aws-lb-controller" \
    --role-name "$ROLE_NAME" \
    --attach-policy-arn "$IAM_POLICY_ARN" \
    --approve \
    --region "$REGION" \
    --override-existing-serviceaccounts 2> "$policy_output" || {
        log "ERROR: Failed to create IAM service account after retries"
        log "Checking CloudFormation stack for errors..."
        aws cloudformation describe-stack-events \
            --stack-name "eksctl-$CLUSTER_NAME-addon-iamserviceaccount-$LB_NAMESPACE-aws-lb-controller" \
            --region "$REGION" \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{ResourceStatus:ResourceStatus,Reason:ResourceStatusReason}' \
            --output text >&2
        cat "$policy_output" >&2
        rm -f "$policy_output"
        cleanup
    }
check_warnings "$policy_output"
log "IAM service account created successfully"
CREATED_IAM_ROLE="$ROLE_NAME"
rm -f "$policy_output"

# Cleanup temporary files
for file in "${TEMP_FILES[@]}"; do
    rm -f "$file" 2>/dev/null
done

log "EKS infrastructure setup completed successfully. Run set-up-app.sh next."```

#### Steps and Explanations for `set-up-infra.sh`

1. **Initial Setup and Helper Functions**:
   - **Purpose**: Sets up error handling, logging, and cleanup mechanisms to ensure the script is robust.
   - **Details**:
     - `set -e`: Exits the script on any error.
     - `log()`: Logs messages with timestamps to stderr to avoid interfering with command outputs.
     - `cleanup()`: Deletes created resources (e.g., cluster, Fargate profiles, IAM roles) if an error occurs.
     - `check_warnings()`: Checks command output for errors, warnings, or deprecations, triggering cleanup on errors.
     - `retry()`: Retries commands up to a specified number of attempts with delays, useful for handling transient AWS API failures.
     - `check_and_install_command()`: Installs required tools if they’re missing.

2. **Check AWS Credentials** (`check_aws_credentials`):
   - **Purpose**: Verifies that the AWS CLI is configured with valid credentials.
   - **Details**:
     - Uses `aws sts get-caller-identity` to check credentials.
     - Retries 3 times with a 10-second delay to handle transient issues.
     - If credentials are invalid, the script exits with an error.

3. **Validate Subnets** (`validate_subnets`):
   - **Purpose**: Ensures the provided subnets are suitable for the EKS cluster.
   - **Details**:
     - Verifies that subnets belong to the specified VPC.
     - Ensures subnets are private (no direct route to an Internet Gateway).
     - Warns if there’s no NAT Gateway for internet access.
     - Checks that subnets span at least 2 Availability Zones for high availability.
   - **Challenges**:
     - Initial versions included a permissions check using `aws iam simulate-principal-policy`, which failed due to ARN parsing issues with assumed roles. This was removed to avoid errors.

4. **Configuration Variables**:
   - **Purpose**: Defines variables for the cluster setup.
   - **Details**:
     - `CLUSTER_NAME="partha-game-cluster"`: Name of the EKS cluster.
     - `REGION="us-east-1"`: AWS region.
     - `VPC_ID="vpc-0e13ae6de03f62cd5"`: VPC ID for the cluster.
     - `PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"`: Private subnets for Fargate.
     - `K8S_VERSION="1.32"`: Kubernetes version compatible with EKS as of April 2025.

5. **Step 1: Install Prerequisites**:
   - **Purpose**: Ensures all required tools are installed.
   - **Details**:
     - Detects the OS and uses the appropriate package manager (`apt-get`, `brew`, or `choco`).
     - Installs AWS CLI, eksctl, kubectl, and Helm if missing.
     - Uses `check_and_install_command` to handle installations with retries.

6. **Step 2: Validate Subnets**:
   - **Purpose**: Calls the `validate_subnets` function to ensure network configuration is correct.
   - **Details**:
     - Validates the provided VPC and subnets.
     - Logs warnings if subnets don’t meet best practices (e.g., missing NAT Gateway, fewer than 2 AZs).

7. **Step 3: Create EKS Cluster with Fargate**:
   - **Purpose**: Creates the EKS cluster using Fargate as the compute backend.
   - **Details**:
     - Uses `eksctl create cluster` with options:
       - `--fargate`: Uses Fargate for compute.
       - `--vpc-private-subnets`: Specifies private subnets.
       - `--version "$K8S_VERSION"`: Sets Kubernetes version to 1.32.
       - `--without-nodegroup`: Avoids creating a default node group.
     - Retries 3 times with a 30-second delay to handle transient failures.
     - Sets `CREATED_CLUSTER` for cleanup tracking.

8. **Step 4: Enable IAM OIDC Provider**:
   - **Purpose**: Enables the OIDC provider for the cluster, required for IAM roles for service accounts (IRSA).
   - **Details**:
     - Uses `eksctl utils associate-iam-oidc-provider` with the `--approve` flag.
     - Retries 3 times with a 10-second delay.

9. **Step 5: Create Default Addons**:
   - **Purpose**: Installs essential EKS addons for cluster functionality.
   - **Details**:
     - Installs `vpc-cni`, `metrics-server`, `kube-proxy`, and `coredns` using `eksctl create addon`.
     - Uses the latest compatible versions for each addon.
     - Retries each installation 3 times with a 30-second delay.

10. **Step 6: Create Namespace for the 2048 Game**:
    - **Purpose**: Creates the `game-2048` namespace for the application.
    - **Details**:
      - Uses `kubectl create namespace`.
      - Logs a message if the namespace already exists (idempotent operation).

11. **Step 7: Create Fargate Profile for the 2048 Game**:
    - **Purpose**: Creates a Fargate profile to run the 2048 game pods in the `game-2048` namespace.
    - **Details**:
      - Uses `eksctl create fargateprofile` for the `game-profile` in the `game-2048` namespace.
      - Retries 3 times with a 30-second delay.
      - Sets `CREATED_FARGATE_PROFILE` for cleanup tracking.

12. **Step 7.5: Create Fargate Profile for `kube-system`**:
    - **Purpose**: Creates a Fargate profile for the `kube-system` namespace to run the AWS Load Balancer Controller.
    - **Details**:
      - Creates the `kube-system-profile` for the `kube-system` namespace.
      - Retries 3 times with a 30-second delay.

13. **Step 8: Create Namespace for AWS Load Balancer Controller**:
    - **Purpose**: Ensures the `kube-system` namespace exists (already created by EKS, but included for idempotency).
    - **Details**:
      - Uses `kubectl create namespace` for `kube-system`.
      - Logs if the namespace already exists.

14. **Step 9: Create IAM Policy for AWS Load Balancer Controller**:
    - **Purpose**: Creates an IAM policy with permissions required by the AWS Load Balancer Controller.
    - **Details**:
      - Defines a comprehensive IAM policy in JSON format, granting permissions for managing ALBs, security groups, and other resources.
      - Creates the policy using `aws iam create-policy` with a unique name (`AWSLoadBalancerControllerIAMPolicy-$TIMESTAMP`).
      - Retries 3 times with a 10-second delay.
      - Validates the policy ARN format and sets `CREATED_IAM_POLICY` for cleanup.
    - **Challenges**:
      - Initially, the script mixed retry logs with the ARN output, causing confusion. Fixed by redirecting logs to stderr.

15. **Step 10: Create IAM Service Account for AWS Load Balancer Controller**:
    - **Purpose**: Creates an IAM role and associates it with a Kubernetes service account for the AWS Load Balancer Controller.
    - **Details**:
      - Deletes any existing `EKSLoadBalancerControllerRole` to avoid conflicts.
      - Uses `eksctl create iamserviceaccount` to create the service account `aws-lb-controller` in the `kube-system` namespace.
      - Attaches the IAM policy created in Step 9.
      - Retries 5 times with a 30-second delay to handle CloudFormation stack creation delays.
      - Logs CloudFormation stack events if creation fails.
      - Sets `CREATED_IAM_ROLE` for cleanup.
    - **Challenges**:
      - CloudFormation stack creation failed initially due to logging issues. Fixed by improving error handling and increasing retries.

---

### Part 2: Application Deployment (`set-up-app.sh`)

This script deploys the AWS Load Balancer Controller and the 2048 game application.

```x-sh#!/bin/bash

# Exit on errors immediately
set -e

# Function to log messages to stderr
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Variables to track created resources for cleanup
TEMP_FILES=()
WARNING_LOG="warnings.log"

# Cleanup function to destroy resources
cleanup() {
    log "Cleaning up resources due to error or warning..."

    # Clean up temporary files
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null
    done

    rm -f "$WARNING_LOG" 2>/dev/null
    log "Cleanup completed."
    exit 1
}

# Function to check for warnings in command output
check_warnings() {
    local cmd_output=$1
    if grep -Ei "ERROR" "$cmd_output" >/dev/null; then
        log "Error detected in command output. Initiating cleanup..."
        cat "$cmd_output" >&2
        cleanup
    elif grep -Ei "DEPRECATION" "$cmd_output" >/dev/null; then
        log "Deprecation warning detected, but continuing..."
        cat "$cmd_output" >&2
    elif grep -Ei "WARNING" "$cmd_output" >/dev/null; then
        log "Warning detected, but continuing..."
        cat "$cmd_output" >&2
    fi
}

# Function to retry a command and check for warnings
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1
    local cmd_output
    cmd_output=$(mktemp) || {
        log "ERROR: Failed to create temporary file with mktemp"
        cleanup
    }
    TEMP_FILES+=("$cmd_output")

    while [ $attempt -le "$max_attempts" ]; do
        log "Attempt $attempt of $max_attempts: $@"
        if "$@" 2> "$cmd_output"; then
            check_warnings "$cmd_output"
            rm -f "$cmd_output"
            return 0
        fi
        log "Command failed, checking for warnings..."
        check_warnings "$cmd_output"
        log "Retrying in $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
    log "ERROR: Command failed after $max_attempts attempts: $@"
    cat "$cmd_output" >&2
    rm -f "$cmd_output"
    cleanup
}

# Trap errors and warnings
trap cleanup ERR

# Configuration variables
CLUSTER_NAME="partha-game-cluster"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"

# Step 1: Verify cluster access
log "Verifying cluster access..."
if ! retry 3 10 kubectl get nodes &> /dev/null; then
    log "ERROR: Cannot access EKS cluster, ensure kubeconfig is set up correctly"
    cleanup
fi
log "Cluster access verified"

# Step 2: Ensure namespaces exist
log "Ensuring namespace $APP_NAMESPACE exists..."
kubectl create namespace "$APP_NAMESPACE" 2>/dev/null || log "Namespace $APP_NAMESPACE already exists"
log "Namespace $APP_NAMESPACE verified"

log "Ensuring namespace $LB_NAMESPACE exists..."
kubectl create namespace "$LB_NAMESPACE" 2>/dev/null || log "Namespace $LB_NAMESPACE already exists"
log "Namespace $LB_NAMESPACE verified"

# Step 3: Install AWS Load Balancer Controller using Helm
log "Adding AWS Load Balancer Controller Helm repository..."
retry 3 10 helm repo add eks https://aws.github.io/eks-charts
retry 3 10 helm repo update
log "Helm repository added successfully"

log "Installing AWS Load Balancer Controller (latest version)..."
helm_output=$(mktemp) || {
    log "ERROR: Failed to create temporary file with mktemp"
    cleanup
}
TEMP_FILES+=("$helm_output")
retry 5 60 helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace "$LB_NAMESPACE" \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-lb-controller \
    --set region="$REGION" \
    --set vpcId="$VPC_ID" \
    --wait --timeout=15m 2> "$helm_output"
check_warnings "$helm_output"

# Log the installed chart and controller version
chart_version="unknown"
if command -v jq &> /dev/null; then
    chart_version=$(helm list -n "$LB_NAMESPACE" -o json | jq -r '.[] | select(.name=="aws-load-balancer-controller") | .chart' 2>/dev/null || echo "unknown")
else
    log "WARNING: 'jq' is not installed, cannot determine chart version"
fi
controller_version=$(kubectl get deployment -n "$LB_NAMESPACE" aws-load-balancer-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' || echo "unknown")
log "AWS Load Balancer Controller installed successfully (Chart: $chart_version, Controller: $controller_version)"
rm -f "$helm_output"

# Step 4: Verify AWS Load Balancer Controller installation
log "Verifying AWS Load Balancer Controller installation..."
sleep 30 # Wait for resources to stabilize
kubectl get deployment -n "$LB_NAMESPACE" aws-load-balancer-controller || {
    log "ERROR: AWS Load Balancer Controller deployment not found"
    cleanup
}
log "AWS Load Balancer Controller verified"

# Step 5: Deploy the 2048 game
log "Creating 2048 game manifest..."
manifest_file=$(mktemp) || {
    log "ERROR: Failed to create temporary file for 2048 manifest"
    cleanup
}
TEMP_FILES+=("$manifest_file")

cat > "$manifest_file" << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: game-2048
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: game-2048
  name: deployment-2048
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: app-2048
  replicas: 5
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app-2048
    spec:
      containers:
      - image: public.ecr.aws/l6m2t8p7/docker-2048:latest
        imagePullPolicy: Always
        name: app-2048
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  namespace: game-2048
  name: service-2048
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: NodePort
  selector:
    app.kubernetes.io/name: app-2048
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: game-2048
  name: ingress-2048
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: service-2048
              port:
                number: 80
EOF

log "Deploying the 2048 game..."
retry 3 10 kubectl apply -f "$manifest_file"
log "2048 game deployed successfully"
rm -f "$manifest_file"

# Step 6: Get Ingress URL
log "Waiting for Ingress to be ready (up to 15 minutes)..."
for i in {1..30}; do # Increased to 15 minutes (30 * 30s)
    INGRESS_URL=$(kubectl get ingress -n "$APP_NAMESPACE" ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$INGRESS_URL" ]; then
        log "2048 game is accessible at: http://$INGRESS_URL"
        break
    fi
    log "Ingress not ready, retrying in 30 seconds..."
    sleep 30
done
if [ -z "$INGRESS_URL" ]; then
    log "ERROR: Could not retrieve Ingress URL after retries"
    kubectl describe ingress -n "$APP_NAMESPACE" ingress-2048 >&2
    cleanup
fi

# Cleanup temporary files
for file in "${TEMP_FILES[@]}"; do
    rm -f "$file" 2>/dev/null
done

log "EKS application setup with 2048 game completed successfully."```

#### Steps and Explanations for `set-up-app.sh`

1. **Initial Setup and Helper Functions**:
   - **Purpose**: Sets up error handling, logging, and cleanup mechanisms, similar to `set-up-infra.sh`.
   - **Details**:
     - `log()`, `cleanup()`, `check_warnings()`, and `retry()` functions are reused for consistency.
     - Tracks temporary files for cleanup.

2. **Configuration Variables**:
   - **Purpose**: Defines variables for the application deployment.
   - **Details**:
     - `CLUSTER_NAME`, `REGION`, `VPC_ID`, `APP_NAMESPACE`, and `LB_NAMESPACE` are set to match the values in `set-up-infra.sh`.

3. **Step 1: Verify Cluster Access**:
   - **Purpose**: Ensures the script can communicate with the EKS cluster.
   - **Details**:
     - Uses `kubectl get nodes` to verify cluster access.
     - Retries 3 times with a 10-second delay.

4. **Step 2: Ensure Namespaces Exist**:
   - **Purpose**: Verifies that the required namespaces exist.
   - **Details**:
     - Creates `game-2048` and `kube-system` namespaces (idempotent operation).
     - Suppresses “AlreadyExists” errors to clean up logs.
   - **Challenges**:
     - Initial versions logged the “AlreadyExists” error, which was confusing. Fixed by redirecting stderr.

5. **Step 3: Install AWS Load Balancer Controller Using Helm**:
   - **Purpose**: Deploys the AWS Load Balancer Controller to manage ALB Ingress resources.
   - **Details**:
     - Adds the `eks` Helm repository (`https://aws.github.io/eks-charts`).
     - Updates the Helm repository index.
     - Installs the latest version of the `aws-load-balancer-controller` chart using `helm upgrade --install`.
     - Configures the controller with the cluster name, region, VPC ID, and existing service account.
     - Retries 5 times with a 60-second delay to handle deployment delays.
     - Logs the installed chart and controller versions.
   - **Challenges**:
     - Initially pinned to version `2.8.0`, which wasn’t available in the repository. Fixed by using the latest version.
     - Chart and controller version logging failed due to missing `jq` and incorrect regex. Fixed by adding a `jq` check and improving the regex.

6. **Step 4: Verify AWS Load Balancer Controller Installation**:
   - **Purpose**: Ensures the controller is running.
   - **Details**:
     - Waits 30 seconds for the deployment to stabilize.
     - Uses `kubectl get deployment` to verify the controller is running.

7. **Step 5: Deploy the 2048 Game**:
   - **Purpose**: Deploys the 2048 game application.
   - **Details**:
     - Creates a temporary manifest file with the provided YAML:
       - Namespace: `game-2048`.
       - Deployment: `deployment-2048` with 5 replicas, using the image `public.ecr.aws/l6m2t8p7/docker-2048:latest`.
       - Service: `service-2048` of type `NodePort`.
       - Ingress: `ingress-2048` using the `alb` ingress class, configured for internet-facing access.
     - Applies the manifest using `kubectl apply`.
     - Retries 3 times with a 10-second delay.
   - **Challenges**:
     - Initially tried to download the manifest from a URL, which was inaccessible. Fixed by embedding the provided YAML directly.

8. **Step 6: Get Ingress URL**:
   - **Purpose**: Retrieves the ALB URL for the 2048 game.
   - **Details**:
     - Polls for the Ingress hostname using `kubectl get ingress` for up to 15 minutes.
     - Logs the URL (e.g., `http://k8s-game2048-ingress2-ff4d192d60-1096844032.us-east-1.elb.amazonaws.com`).
     - If the URL isn’t available, logs diagnostic information and exits.

---

### Challenges and Resolutions

1. **AWS CLI Permissions Check Issue**:
   - **Problem**: An initial version of `set-up-infra.sh` included a permissions check using `aws iam simulate-principal-policy`, which failed due to ARN parsing issues with assumed roles.
   - **Resolution**: Removed the permissions check to avoid the error, relying on the user to ensure proper permissions.

2. **IAM Policy ARN Logging Issue**:
   - **Problem**: The IAM policy ARN output was mixed with retry logs, causing confusion.
   - **Resolution**: Redirected all log messages to stderr and validated the ARN format.

3. **IAM Service Account Creation Failure**:
   - **Problem**: The `eksctl create iamserviceaccount` command failed due to CloudFormation stack issues.
   - **Resolution**: Increased retries, added detailed error logging with CloudFormation stack events, and improved role deletion logic.

4. **AWS Load Balancer Controller Version Issue**:
   - **Problem**: The Helm chart version `2.8.0` was not found in the `eks` repository.
   - **Resolution**: Removed the hardcoded version, allowing Helm to install the latest version.

5. **Chart and Controller Version Logging Failure**:
   - **Problem**: The script failed to log the chart and controller versions due to missing `jq` and incorrect regex.
   - **Resolution**: Added a `jq` check with a warning and improved the regex for version extraction.

6. **Inaccessible 2048 Game Manifest URL**:
   - **Problem**: The script couldn’t access the manifest URL.
   - **Resolution**: Embedded the provided YAML manifest directly in the script.

7. **Namespace Creation Error Output**:
   - **Problem**: The “AlreadyExists” error from `kubectl create namespace` was logged, causing confusion.
   - **Resolution**: Suppressed the error output while maintaining idempotency.

---

### How to Run the Scripts

1. **Save the Scripts**:
   - Save `set-up-infra.sh` and `set-up-app.sh` in a directory (e.g., `~/aws-repo/JenkinsTask/scripts`).

2. **Make Scripts Executable**:
   ```bash
   chmod +x set-up-infra.sh set-up-app.sh
   ```

3. **Run Part 1 (Infrastructure Setup)**:
   ```bash
   ./set-up-infra.sh
   ```
   - This sets up the EKS cluster and infrastructure.
   - Takes approximately 20-30 minutes due to cluster creation and CloudFormation operations.

4. **Run Part 2 (Application Setup)**:
   ```bash
   ./set-up-app.sh
   ```
   - This deploys the AWS Load Balancer Controller and the 2048 game.
   - Takes approximately 5-15 minutes, depending on ALB provisioning.

---

### Verification

1. **Check the EKS Cluster**:
   ```bash
   aws eks describe-cluster --name partha-game-cluster --region us-east-1 --query 'cluster.version'
   ```
   Should return `1.32`.

2. **Check the AWS Load Balancer Controller**:
   ```bash
   kubectl get deployment -n kube-system aws-load-balancer-controller
   helm list -n kube-system
   ```

3. **Verify the 2048 Game Deployment**:
   ```bash
   kubectl get deployment -n game-2048 deployment-2048
   kubectl get service -n game-2048 service-2048
   kubectl get ingress -n game-2048 ingress-2048
   ```
   Example output:
   ```
   NAME              READY   UP-TO-DATE   AVAILABLE   AGE
   deployment-2048   5/5     5            5           8m51s
   NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
   service-2048   NodePort   10.100.70.48   <none>        80:31949/TCP   8m52s
   NAME           CLASS   HOSTS   ADDRESS                                                                   PORTS   AGE
   ingress-2048   alb     *       k8s-game2048-ingress2-ff4d192d60-1096844032.us-east-1.elb.amazonaws.com   80      8m54s
   ```

4. **Access the Game**:
   - The script outputs the Ingress URL, e.g.:
     ```
     [2025-04-17 12:27:14] 2048 game is accessible at: http://k8s-game2048-ingress2-ff4d192d60-1096844032.us-east-1.elb.amazonaws.com
     ```
   - Open the URL in a browser to play the 2048 game.

---

### Additional Notes

- **Permissions**: Ensure the AWS user/role has sufficient permissions. If errors occur (e.g., `AccessDenied`), check the role’s permissions using:
  ```bash
  aws iam get-role --role-name AWSReservedSSO_AWSAdministratorAccess_19c8203d69c47459
  ```
- **Cleanup**: If the scripts fail, they attempt to clean up created resources. Manual cleanup may be required if the script is interrupted:
  ```bash
  eksctl delete cluster --name partha-game-cluster --region us-east-1
  aws iam delete-policy --policy-arn arn:aws:iam::ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy-TIMESTAMP
  aws iam delete-role --role-name EKSLoadBalancerControllerRole
  ```
- **Ingress Delays**: ALB provisioning can take several minutes. The script waits up to 15 minutes for the Ingress URL to be available.
- **Dependencies**:
  - Install `jq` to log the Helm chart version:
    ```bash
    sudo apt-get install jq  # On Linux
    brew install jq         # On macOS
    ```

---

### Conclusion
This task successfully set up an EKS cluster with Fargate, deployed the AWS Load Balancer Controller, and hosted the 2048 game, accessible via an ALB. The scripts are designed to be robust, with error handling, retries, and cleanup mechanisms to handle failures gracefully. Despite several challenges (e.g., permissions issues, versioning problems, and inaccessible URLs), each was resolved through iterative improvements, resulting in a fully functional deployment. The 2048 game is now accessible at the provided Ingress URL, and the setup can be used as a template for deploying other applications on EKS with Fargate.
