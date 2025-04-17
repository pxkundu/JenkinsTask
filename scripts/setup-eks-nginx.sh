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

# Configuration variables
CLUSTER_NAME="fargate-cluster-partha"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
PRIVATE_SUBNETS="subnet-066008bd872659833,subnet-07b231970a5ea0a3a"
NAMESPACE="nginx-ingress"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")

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

# Step 2: Create EKS cluster with Fargate
log "Creating EKS cluster: $CLUSTER_NAME"
eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --fargate \
    --vpc-private-subnets="$PRIVATE_SUBNETS" \
    --version 1.29 && log "EKS cluster created successfully" || {
        log "WARNING: Failed to create EKS cluster, proceeding with next steps"
    }

# Step 3: Create Fargate profile
log "Creating Fargate profile..."
eksctl create fargateprofile \
    --cluster="$CLUSTER_NAME" \
    --region="$REGION" \
    --name="nginx-ingress-profile" \
    --namespace="$NAMESPACE" \
    --labels app.kubernetes.io/name=nginx-ingress && log "Fargate profile created successfully" || {
        log "WARNING: Failed to create Fargate profile, proceeding anyway"
    }

# Step 4: Create namespace
log "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" && log "Namespace created successfully" || {
    log "WARNING: Namespace $NAMESPACE may already exist, proceeding anyway"
}

# Step 5: Create IAM policy for NGINX Ingress
log "Creating IAM policy for NGINX Ingress..."
cat > nginx-ingress-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:*",
                "ec2:Describe*",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:CreateSecurityGroup",
                "ec2:CreateTags",
                "ec2:DeleteTags",
                "ec2:DeleteSecurityGroup",
                "ec2:DescribeInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeTags",
                "ec2:DescribeVpcs",
                "ec2:ModifyInstanceAttribute",
                "ec2:ModifyNetworkInterfaceAttribute",
                "ec2:RevokeSecurityGroupIngress"
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

# Step 6: Create IAM service account
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

# Step 7: Install NGINX Ingress Controller using Helm
log "Adding NGINX Ingress Helm repository..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update && log "Helm repository added successfully" || {
    log "WARNING: Failed to add Helm repository, proceeding anyway"
}

log "Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace "$NAMESPACE" \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=nginx-ingress-controller \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.service.type=LoadBalancer \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" && log "NGINX Ingress Controller installed successfully" || {
        log "WARNING: Failed to install NGINX Ingress Controller, proceeding anyway"
    }

# Step 8: Verify installation
log "Verifying NGINX Ingress Controller installation..."
sleep 30 # Wait for resources to stabilize
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || log "WARNING: Failed to get pods"
kubectl get services -n "$NAMESPACE" -o wide 2>/dev/null || log "WARNING: Failed to get services"
kubectl get ingressclass 2>/dev/null || log "WARNING: Failed to get ingressclass"

# Step 9: Deploy test application
log "Deploying test application..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-app-service
  namespace: $NAMESPACE
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: test-app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-app-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app-service
            port:
              number: 80
EOF
[ $? -eq 0 ] && log "Test application deployed successfully" || log "WARNING: Failed to deploy test application"

# Step 10: Get Ingress URL
log "Waiting for Ingress to be ready..."
sleep 60 # Wait for LoadBalancer to be provisioned
INGRESS_URL=$(kubectl get svc -n "$NAMESPACE" ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$INGRESS_URL" ]; then
    log "NGINX Ingress Controller is accessible at: http://$INGRESS_URL"
else
    log "WARNING: Could not retrieve Ingress URL"
fi

# Cleanup temporary files
rm -f nginx-ingress-policy.json 2>/dev/null

log "EKS cluster with NGINX Ingress Controller setup completed. Check warnings for any issues."
