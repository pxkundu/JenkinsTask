#!/bin/bash

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

# Static configuration values
CLUSTER_NAME="game-cluster-partha"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"
K8S_VERSION="1.32"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"

# Additional variables
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%s)
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-$TIMESTAMP"

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

# Step 2: Create EKS cluster with Fargate
log "Creating EKS cluster: $CLUSTER_NAME with Kubernetes version $K8S_VERSION in region $REGION"
retry 3 30 eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --fargate \
    --vpc-private-subnets="$PRIVATE_SUBNETS" \
    --version "$K8S_VERSION" \
    --without-nodegroup
log "EKS cluster created successfully"
CREATED_CLUSTER="$CLUSTER_NAME"

# Step 3: Enable IAM OIDC provider
log "Enabling IAM OIDC provider..."
retry 3 10 eksctl utils associate-iam-oidc-provider --region="$REGION" --cluster="$CLUSTER_NAME" --approve
log "IAM OIDC provider enabled successfully"

# Step 4: Create default addons with latest compatible versions
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

# Step 5: Create namespace for the application
log "Creating namespace: $APP_NAMESPACE"
kubectl create namespace "$APP_NAMESPACE" || log "Namespace $APP_NAMESPACE already exists"
log "Namespace created successfully"

# Step 6: Create Fargate profile for the application
log "Creating Fargate profile for the application..."
retry 3 30 eksctl create fargateprofile \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name "app-profile" \
    --namespace "$APP_NAMESPACE"
log "Fargate profile created successfully"
CREATED_FARGATE_PROFILE="app-profile"

# Step 6.5: Create Fargate profile for load balancer namespace
log "Creating Fargate profile for $LB_NAMESPACE..."
retry 3 30 eksctl create fargateprofile \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name "lb-profile" \
    --namespace "$LB_NAMESPACE"
log "Fargate profile for $LB_NAMESPACE created successfully"
CREATED_FARGATE_PROFILE="lb-profile"

# Step 7: Create namespace for AWS Load Balancer Controller
log "Creating namespace: $LB_NAMESPACE"
kubectl create namespace "$LB_NAMESPACE" || log "Namespace $LB_NAMESPACE already exists"
log "Namespace created successfully"

# Step 8: Create IAM policy for AWS Load Balancer Controller with a unique name
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

# Step 9: Create IAM service account for AWS Load Balancer Controller
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

log "EKS infrastructure setup completed successfully. Run set-up-app.sh next."
