#!/bin/bash
set -e

# Logging function with type
log() {
    local type="$1"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$type] $message" >&2
}

# Command execution with output capture
run_command() {
    local cmd="$@"
    local output_file
    output_file=$(mktemp)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create temp file"
        cleanup
    fi
    TEMP_FILES+=("$output_file")
    log "COMMAND" "$cmd"
    if eval "$cmd" >"$output_file" 2>&1; then
        local response=$(head -n 5 "$output_file" | tr '\n' ' ')
        [[ -z "$response" ]] && response="Command completed successfully (no output)"
        log "RESPONSE" "$response"
        rm -f "$output_file"
        return 0
    else
        log "WARNING" "Command failed, but continuing cleanup. Full output in $output_file"
        cat "$output_file" >&2
        rm -f "$output_file"
        return 1
    fi
}

# Initialize variables
CREATED_CLUSTER=""
CREATED_FARGATE_PROFILE=""
CREATED_IAM_ROLE=""
CREATED_IAM_POLICY=""
TEMP_FILES=()
WARNING_LOG="warnings.log"
CLUSTER_NAME="partha-game-cluster"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"
K8S_VERSION="1.32"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"
log "INFO" "Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
log "INFO" "ACCOUNT_ID=$ACCOUNT_ID"
TIMESTAMP=$(date +%s)
IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-$TIMESTAMP"
log "INFO" "TIMESTAMP=$TIMESTAMP, IAM_POLICY_NAME=$IAM_POLICY_NAME"

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up resources due to error or warning..."
    if [ -n "$CREATED_FARGATE_PROFILE" ]; then
        log "INFO" "Deleting Fargate profile: $CREATED_FARGATE_PROFILE..."
        run_command "eksctl delete fargateprofile --cluster \"$CLUSTER_NAME\" --name \"$CREATED_FARGATE_PROFILE\" --region \"$REGION\" --wait" || true
    fi
    if [ -n "$CREATED_IAM_ROLE" ]; then
        log "INFO" "Deleting IAM role: $CREATED_IAM_ROLE..."
        attached_policies=$(aws iam list-attached-role-policies --role-name "$CREATED_IAM_ROLE" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || true)
        for policy_arn in $attached_policies; do
            run_command "aws iam detach-role-policy --role-name \"$CREATED_IAM_ROLE\" --policy-arn \"$policy_arn\"" || true
        done
        inline_policies=$(aws iam list-role-policies --role-name "$CREATED_IAM_ROLE" --query 'PolicyNames' --output text 2>/dev/null || true)
        for policy_name in $inline_policies; do
            run_command "aws iam delete-role-policy --role-name \"$CREATED_IAM_ROLE\" --policy-name \"$policy_name\"" || true
        done
        sleep 5
        run_command "aws iam delete-role --role-name \"$CREATED_IAM_ROLE\"" || true
    fi
    if [ -n "$CREATED_IAM_POLICY" ]; then
        log "INFO" "Deleting IAM policy: $CREATED_IAM_POLICY..."
        run_command "aws iam delete-policy --policy-arn \"$CREATED_IAM_POLICY\"" || true
    fi
    if [ -n "$CREATED_CLUSTER" ]; then
        log "INFO" "Deleting cluster: $CREATED_CLUSTER..."
        run_command "eksctl delete cluster --name \"$CREATED_CLUSTER\" --region \"$REGION\" --wait" || true
    fi
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null
    done
    rm -f "$WARNING_LOG" 2>/dev/null
    log "INFO" "Cleanup completed."
    exit 1
}

# Check warnings in command output
check_warnings() {
    local cmd_output="$1"
    if grep -Ei "ERROR" "$cmd_output" >/dev/null; then
        log "ERROR" "Error detected in command output. Initiating cleanup..."
        cat "$cmd_output" >&2
        cleanup
    elif grep -Ei "DEPRECATION" "$cmd_output" >/dev/null; then
        log "WARNING" "Deprecation warning detected, but continuing..."
        cat "$cmd_output" >&2
    elif grep -Ei "WARNING" "$cmd_output" >/dev/null; then
        log "WARNING" "Warning detected, but continuing..."
        cat "$cmd_output" >&2
    fi
}

# Retry function using run_command
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1
    local cmd_output
    cmd_output=$(mktemp)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create temp file"
        cleanup
    fi
    TEMP_FILES+=("$cmd_output")
    while [ $attempt -le "$max_attempts" ]; do
        log "INFO" "Attempt $attempt of $max_attempts for command: $@"
        if run_command "$@" 2>"$cmd_output"; then
            check_warnings "$cmd_output"
            rm -f "$cmd_output"
            return 0
        fi
        log "INFO" "Command failed, checking for warnings..."
        check_warnings "$cmd_output"
        log "INFO" "Retrying in $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
    log "ERROR" "Command failed after $max_attempts attempts: $@"
    cat "$cmd_output" >&2
    rm -f "$cmd_output"
    cleanup
}

trap cleanup ERR

# Install prerequisites
check_and_install_command() {
    local cmd="$1"
    local install_cmd="$2"
    log "INFO" "Checking if $cmd is installed..."
    if command -v "$cmd" &> /dev/null; then
        log "INFO" "$cmd is already installed"
        return 0
    fi
    log "INFO" "Installing $cmd..."
    local install_output
    install_output=$(mktemp)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create temp file"
        cleanup
    fi
    TEMP_FILES+=("$install_output")
    if eval "$install_cmd" 2>"$install_output"; then
        check_warnings "$install_output"
        log "INFO" "$cmd installed successfully"
        rm -f "$install_output"
        return 0
    else
        log "ERROR" "Failed to install $cmd"
        cat "$install_output" >&2
        rm -f "$install_output"
        cleanup
    fi
}

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
    log "ERROR" "Unsupported OS, manual installation required"
    cleanup
fi

check_and_install_command "aws" "
    curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' &&
    unzip awscliv2.zip &&
    sudo ./aws/install &&
    rm -rf awscliv2.zip aws
"
check_and_install_command "eksctl" "
    curl --silent --location 'https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz' | tar xz -C /tmp &&
    sudo mv /tmp/eksctl /usr/local/bin
"
check_and_install_command "kubectl" "
    curl -LO 'https://dl.k8s.io/release/v$K8S_VERSION/bin/linux/amd64/kubectl' &&
    chmod +x kubectl &&
    sudo mv kubectl /usr/local/bin/
"
check_and_install_command "helm" "
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"

# Verify AWS credentials
check_aws_credentials() {
    log "INFO" "Checking AWS credentials..."
    local output
    output=$(mktemp)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create temp file"
        cleanup
    fi
    TEMP_FILES+=("$output")
    if retry 3 10 "aws sts get-caller-identity" > /dev/null 2>"$output"; then
        log "INFO" "AWS credentials are valid"
        rm -f "$output"
        return 0
    else
        log "ERROR" "AWS credentials are not configured properly"
        cat "$output" >&2
        rm -f "$output"
        cleanup
    fi
}
check_aws_credentials

# Create EKS cluster
log "INFO" "Creating EKS cluster: $CLUSTER_NAME with Kubernetes version $K8S_VERSION in region $REGION"
retry 3 30 "eksctl create cluster \
    --name \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --fargate \
    --vpc-private-subnets=\"$PRIVATE_SUBNETS\" \
    --version \"$K8S_VERSION\" \
    --without-nodegroup"
log "INFO" "EKS cluster created successfully"
CREATED_CLUSTER="$CLUSTER_NAME"

# Enable IAM OIDC provider
log "INFO" "Enabling IAM OIDC provider..."
retry 3 10 "eksctl utils associate-iam-oidc-provider --region=\"$REGION\" --cluster \"$CLUSTER_NAME\" --approve"
log "INFO" "IAM OIDC provider enabled successfully"

# Create default addons
log "INFO" "Creating default addons (metrics-server, vpc-cni, kube-proxy, coredns)..."
retry 3 30 "eksctl create addon \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name vpc-cni \
    --version latest"
log "INFO" "Successfully created addon: vpc-cni"
retry 3 30 "eksctl create addon \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name metrics-server \
    --version latest"
log "INFO" "Successfully created addon: metrics-server"
retry 3 30 "eksctl create addon \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name kube-proxy \
    --version latest"
log "INFO" "Successfully created addon: kube-proxy"
retry 3 30 "eksctl create addon \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name coredns \
    --version latest"
log "INFO" "Successfully created addon: coredns"

# Create application namespace
log "INFO" "Creating namespace: $APP_NAMESPACE"
if ! kubectl get namespace "$APP_NAMESPACE" >/dev/null 2>&1; then
    run_command "kubectl create namespace \"$APP_NAMESPACE\""
else
    log "INFO" "Namespace $APP_NAMESPACE already exists"
fi
log "INFO" "Namespace created successfully"

# Create Fargate profile for application
log "INFO" "Creating Fargate profile for the application..."
retry 3 30 "eksctl create fargateprofile \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name app-profile \
    --namespace \"$APP_NAMESPACE\""
log "INFO" "Fargate profile created successfully"
CREATED_FARGATE_PROFILE="app-profile"

# Create Fargate profile for load balancer
log "INFO" "Creating Fargate profile for $LB_NAMESPACE..."
retry 3 30 "eksctl create fargateprofile \
    --cluster \"$CLUSTER_NAME\" \
    --region \"$REGION\" \
    --name lb-profile \
    --namespace \"$LB_NAMESPACE\""
log "INFO" "Fargate profile for $LB_NAMESPACE created successfully"
CREATED_FARGATE_PROFILE="lb-profile"

# Create load balancer namespace
log "INFO" "Creating namespace: $LB_NAMESPACE"
if ! kubectl get namespace "$LB_NAMESPACE" >/dev/null 2>&1; then
    run_command "kubectl create namespace \"$LB_NAMESPACE\""
else
    log "INFO" "Namespace $LB_NAMESPACE already exists"
fi
log "INFO" "Namespace created successfully"

# Create IAM policy for AWS Load Balancer Controller
log "INFO" "Creating IAM policy for AWS Load Balancer Controller with name $IAM_POLICY_NAME..."
cat > aws-lb-controller-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags"
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
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*"
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
                "arn:aws:elasticloadbalancing:*:*:listener/net/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*"
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
                "elasticloadbalancing:DeleteTargetGroup"
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
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
}
EOF
TEMP_FILES+=("aws-lb-controller-policy.json")
policy_output=$(mktemp)
if [ $? -ne 0 ]; then
    log "ERROR" "Failed to create temp file"
    cleanup
fi
TEMP_FILES+=("$policy_output")
# Validate policy JSON if jq is available
if command -v jq >/dev/null 2>&1; then
    log "INFO" "Validating IAM policy JSON with jq..."
    if ! jq empty aws-lb-controller-policy.json >/dev/null 2>"$policy_output"; then
        log "ERROR" "Invalid IAM policy JSON"
        cat "$policy_output" >&2
        rm -f "$policy_output"
        cleanup
    fi
else
    log "WARNING" "jq not found, skipping IAM policy JSON validation. Ensure the JSON is valid to avoid AWS errors."
fi
# Check if policy already exists
log "INFO" "Checking for existing IAM policy $IAM_POLICY_NAME..."
existing_policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].Arn" --output text 2>"$policy_output" || true)
if [ -n "$existing_policy_arn" ]; then
    log "INFO" "Policy $IAM_POLICY_NAME already exists with ARN: $existing_policy_arn"
    log "INFO" "Do you want to delete the existing policy and recreate it? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        run_command "aws iam delete-policy --policy-arn \"$existing_policy_arn\""
        log "INFO" "Deleted existing policy. Recreating..."
    else
        IAM_POLICY_ARN="$existing_policy_arn"
        log "INFO" "Reusing existing policy ARN: $IAM_POLICY_ARN"
    fi
fi
# Create new policy if needed
if [ -z "$IAM_POLICY_ARN" ]; then
    log "INFO" "Creating new IAM policy with name $IAM_POLICY_NAME..."
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "INFO" "Attempt $attempt of $max_attempts to create IAM policy..."
        IAM_POLICY_ARN=$(aws iam create-policy \
            --policy-name "$IAM_POLICY_NAME" \
            --policy-document file://aws-lb-controller-policy.json \
            --query 'Policy.Arn' \
            --output text 2>"$policy_output") && break
        log "ERROR" "Failed to create IAM policy on attempt $attempt. Error details:"
        cat "$policy_output" >&2
        if [ $attempt -eq $max_attempts ]; then
            rm -f "$policy_output"
            log "INFO" "IAM policy creation failed after $max_attempts attempts, but cluster and other resources are intact. Run cleanup.sh to remove resources if needed."
            exit 1
        fi
        log "INFO" "Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
fi
# Validate ARN
if [[ ! "$IAM_POLICY_ARN" =~ ^arn:aws:iam::[0-9]{12}:policy/[A-Za-z0-9-]+ ]]; then
    log "ERROR" "Invalid IAM policy ARN: $IAM_POLICY_ARN. Error details:"
    cat "$policy_output" >&2
    rm -f "$policy_output"
    log "INFO" "IAM policy creation failed, but cluster and other resources are intact. Run cleanup.sh to remove resources if needed."
    exit 1
fi
log "INFO" "IAM policy created or reused successfully with ARN: $IAM_POLICY_ARN"
CREATED_IAM_POLICY="$IAM_POLICY_ARN"
rm -f "$policy_output"

# Create IAM service account
log "INFO" "Creating IAM service account for AWS Load Balancer Controller..."
ROLE_NAME="EKSLoadBalancerControllerRole"
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    log "INFO" "IAM role $ROLE_NAME already exists, deleting it..."
    attached_policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
    for policy_arn in $attached_policies; do
        retry 3 10 "aws iam detach-role-policy --role-name \"$ROLE_NAME\" --policy-arn \"$policy_arn\""
    done
    inline_policies=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null)
    for policy_name in $inline_policies; do
        retry 3 10 "aws iam delete-role-policy --role-name \"$ROLE_NAME\" --policy-name \"$policy_name\""
    done
    sleep 5
    retry 3 10 "aws iam delete-role --role-name \"$ROLE_NAME\""
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "ERROR" "Failed to delete IAM role $ROLE_NAME"
        cleanup
    fi
fi
retry 5 30 "eksctl create iamserviceaccount \
    --cluster \"$CLUSTER_NAME\" \
    --namespace \"$LB_NAMESPACE\" \
    --name aws-lb-controller \
    --role-name \"$ROLE_NAME\" \
    --attach-policy-arn \"$IAM_POLICY_ARN\" \
    --approve \
    --region \"$REGION\" \
    --override-existing-serviceaccounts"
log "INFO" "IAM service account created successfully"
CREATED_IAM_ROLE="$ROLE_NAME"

# Clean up temporary files
for file in "${TEMP_FILES[@]}"; do
    rm -f "$file" 2>/dev/null
done
log "INFO" "EKS infrastructure setup completed successfully. Run set-up-app.sh next."
