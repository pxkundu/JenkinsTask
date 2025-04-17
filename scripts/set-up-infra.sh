#!/bin/bash

# Do not exit on errors, handle them gracefully
set +e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check and install command if missing
check_and_install_command() {
    local cmd=$1
    local install_cmd=$2
    if command -v "$cmd" &> /dev/null; then
        log "$cmd is already installed"
        return 0
    fi
    log "Installing $cmd..."
    if eval "$install_cmd"; then
        log "$cmd installed successfully"
        return 0
    else
        log "WARNING: Failed to install $cmd, proceeding anyway"
        return 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    if aws sts get-caller-identity &> /dev/null; then
        log "AWS credentials are valid"
        return 0
    else
        log "WARNING: AWS credentials are not configured properly, some steps may fail"
        return 1
    fi
}

# Function to validate subnets
validate_subnets() {
    local vpc_id=$1
    local subnets=$2
    log "Validating subnets: $subnets"
    IFS=',' read -ra SUBNET_ARRAY <<< "$subnets"
    for subnet in "${SUBNET_ARRAY[@]}"; do
        if ! aws ec2 describe-subnets --subnet-ids "$subnet" --query 'Subnets[0].VpcId' --output text 2>/dev/null | grep -q "$vpc_id"; then
            log "ERROR: Subnet $subnet does not belong to VPC $vpc_id or is invalid"
            return 1
        fi
        if aws ec2 describe-route-tables --filters Name=association.subnet-id,Values="$subnet" --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0` && GatewayId!=`null`]' --output text 2>/dev/null | grep -q "igw-"; then
            log "WARNING: Subnet $subnet is public, but private subnets are recommended for Fargate"
        fi
    done
    log "Subnets validated successfully"
    return 0
}

# Configuration variables
CLUSTER_NAME="fargate-cluster-partha"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"
NAMESPACE="nginx-ingress"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
K8S_VERSION=${K8S_VERSION:-1.30} # Default to 1.30, override with env variable

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
else
    log "WARNING: Unsupported OS, manual installation may be required for some tools"
    PKG_MANAGER="unknown"
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
    curl -LO 'https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl' &&
    chmod +x kubectl &&
    sudo mv kubectl /usr/local/bin/
"

# Install helm
check_and_install_command "helm" "
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"

check_aws_credentials

# Step 2: Validate subnets
validate_subnets "$VPC_ID" "$PRIVATE_SUBNETS" || {
    log "WARNING: Subnet validation failed, proceeding with provided subnets"
}

# Step 3: Create EKS cluster with Fargate
log "Creating EKS cluster: $CLUSTER_NAME with Kubernetes version $K8S_VERSION"
eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --fargate \
    --vpc-private-subnets="$PRIVATE_SUBNETS" \
    --version "$K8S_VERSION" && log "EKS cluster created successfully" || {
        log "WARNING: Failed to create EKS cluster, proceeding with next steps"
    }

# Step 4: Enable IAM OIDC provider
log "Enabling IAM OIDC provider..."
if ! eksctl utils associate-iam-oidc-provider --region="$REGION" --cluster="$CLUSTER_NAME" --approve; then
    log "WARNING: Failed to enable IAM OIDC provider, service account creation may fail"
else
    log "IAM OIDC provider enabled successfully"
fi

# Step 5: Create Fargate profile
log "Creating Fargate profile..."
eksctl create fargateprofile \
    --cluster="$CLUSTER_NAME" \
    --region="$REGION" \
    --name="nginx-ingress-profile" \
    --namespace="$NAMESPACE" \
    --labels app.kubernetes.io/name=nginx-ingress && log "Fargate profile created successfully" || {
        log "WARNING: Failed to create Fargate profile, proceeding anyway"
    }

# Step 6: Create namespace
log "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" && log "Namespace created successfully" || {
    log "WARNING: Namespace $NAMESPACE may already exist, proceeding anyway"
}

# Step 7: Create IAM policy for NGINX Ingress (using AWS Load Balancer Controller policy)
log "Creating IAM policy for NGINX Ingress..."
cat > nginx-ingress-policy.json << EOF
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
                "elasticloadbalancing:DescribeTrustStores"
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
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*"
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

POLICY_ARN=$(aws iam create-policy \
    --policy-name NGINXIngressControllerPolicy \
    --policy-document file://nginx-ingress-policy.json \
    --query 'Policy.Arn' \
    --output text 2>/dev/null) && log "IAM policy created successfully" || {
        log "WARNING: Failed to create IAM policy, proceeding anyway"
        POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/NGINXIngressControllerPolicy"
    }

# Step 8: Create IAM service account
log "Creating IAM service account..."
eksctl create iamserviceaccount \
    --cluster="$CLUSTER_NAME" \
    --namespace="$NAMESPACE" \
    --name="nginx-ingress-controller" \
    --role-name="NGINXIngressControllerRole" \
    --attach-policy-arn="$POLICY_ARN" \
    --approve \
    --region="$REGION" \
    --override-existing-serviceaccounts && log "IAM service account created successfully" || {
        log "WARNING: Failed to create IAM service account, proceeding anyway"
    }

# Cleanup temporary files
rm -f nginx-ingress-policy.json 2>/dev/null

log "EKS infrastructure setup completed. Check warnings for any issues. Run setup-eks-app.sh next."
