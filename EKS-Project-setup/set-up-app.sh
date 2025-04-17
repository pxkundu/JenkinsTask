#!/bin/bash

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

# Function to validate AWS region
validate_region() {
    local region=$1
    log "Validating AWS region: $region..."
    if aws ec2 describe-regions --region-names "$region" --query 'Regions[0].RegionName' --output text 2>/dev/null | grep -q "$region"; then
        log "Region $region is valid"
        return 0
    else
        log "ERROR: Invalid AWS region: $region"
        cleanup
    fi
}

# Function to validate VPC ID
validate_vpc() {
    local vpc_id=$1
    local region=$2
    log "Validating VPC ID: $vpc_id..."
    if [[ ! "$vpc_id" =~ ^vpc-[0-9a-f]{17}$ ]]; then
        log "ERROR: VPC ID $vpc_id does not match expected format (e.g., vpc-0e13ae6de03f62cd5)"
        cleanup
    fi
    if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$region" --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q "$vpc_id"; then
        log "VPC ID $vpc_id is valid"
        return 0
    else
        log "ERROR: VPC ID $vpc_id does not exist in region $region"
        cleanup
    fi
}

# Function to validate namespace name
validate_namespace() {
    local namespace=$1
    log "Validating namespace: $namespace..."
    if [[ ! "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        log "ERROR: Namespace $namespace is invalid. It must be lowercase, start and end with alphanumeric characters, and can contain hyphens in between."
        cleanup
    fi
    if [ ${#namespace} -gt 63 ]; then
        log "ERROR: Namespace $namespace is too long. It must be 63 characters or less."
        cleanup
    fi
    log "Namespace $namespace is valid"
}

# Prompt for user inputs
echo "Please provide the following details to deploy the application on the EKS cluster:"
echo "Ensure these match the values used in set-up-infra.sh for cluster name, region, VPC ID, and namespaces."
echo ""

# Cluster Name
while true; do
    read -p "Enter the EKS cluster name (e.g., my-game-cluster): " CLUSTER_NAME
    if [[ -z "$CLUSTER_NAME" ]]; then
        echo "Cluster name cannot be empty. Please try again."
    elif [[ ! "$CLUSTER_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo "Cluster name can only contain alphanumeric characters and hyphens. Please try again."
    elif [ ${#CLUSTER_NAME} -gt 100 ]; then
        echo "Cluster name is too long. It must be 100 characters or less. Please try again."
    else
        break
    fi
done

# AWS Region
while true; do
    read -p "Enter the AWS region (e.g., us-east-1): " REGION
    if [[ -z "$REGION" ]]; then
        echo "Region cannot be empty. Please try again."
    else
        validate_region "$REGION"
        break
    fi
done

# VPC ID
while true; do
    read -p "Enter the VPC ID (e.g., vpc-0e13ae6de03f62cd5): " VPC_ID
    if [[ -z "$VPC_ID" ]]; then
        echo "VPC ID cannot be empty. Please try again."
    else
        validate_vpc "$VPC_ID" "$REGION"
        break
    fi
done

# Application Namespace
while true; do
    read -p "Enter the namespace for the application (default: game-2048): " APP_NAMESPACE
    APP_NAMESPACE=${APP_NAMESPACE:-game-2048}
    validate_namespace "$APP_NAMESPACE"
    break
done

# Load Balancer Namespace
while true; do
    read -p "Enter the namespace for the load balancer controller (default: kube-system): " LB_NAMESPACE
    LB_NAMESPACE=${LB_NAMESPACE:-kube-system}
    validate_namespace "$LB_NAMESPACE"
    break
done

# Container Image for the Application
while true; do
    read -p "Enter the container image for the application (default: public.ecr.aws/l6m2t8p7/docker-2048:latest): " APP_IMAGE
    APP_IMAGE=${APP_IMAGE:-public.ecr.aws/l6m2t8p7/docker-2048:latest}
    if [[ -z "$APP_IMAGE" ]]; then
        echo "Container image cannot be empty. Please try again."
    else
        break
    fi
done

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

# Step 5: Deploy the application
log "Creating application manifest..."
manifest_file=$(mktemp) || {
    log "ERROR: Failed to create temporary file for application manifest"
    cleanup
}
TEMP_FILES+=("$manifest_file")

cat > "$manifest_file" << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: $APP_NAMESPACE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: $APP_NAMESPACE
  name: deployment-app
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: app
  replicas: 5
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app
    spec:
      containers:
      - image: $APP_IMAGE
        imagePullPolicy: Always
        name: app
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  namespace: $APP_NAMESPACE
  name: service-app
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: NodePort
  selector:
    app.kubernetes.io/name: app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: $APP_NAMESPACE
  name: ingress-app
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
              name: service-app
              port:
                number: 80
EOF

log "Deploying the application..."
retry 3 10 kubectl apply -f "$manifest_file"
log "Application deployed successfully"
rm -f "$manifest_file"

# Step 6: Get Ingress URL
log "Waiting for Ingress to be ready (up to 15 minutes)..."
for i in {1..30}; do # Increased to 15 minutes (30 * 30s)
    INGRESS_URL=$(kubectl get ingress -n "$APP_NAMESPACE" ingress-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$INGRESS_URL" ]; then
        log "Application is accessible at: http://$INGRESS_URL"
        break
    fi
    log "Ingress not ready, retrying in 30 seconds..."
    sleep 30
done
if [ -z "$INGRESS_URL" ]; then
    log "ERROR: Could not retrieve Ingress URL after retries"
    kubectl describe ingress -n "$APP_NAMESPACE" ingress-app >&2
    cleanup
fi

# Cleanup temporary files
for file in "${TEMP_FILES[@]}"; do
    rm -f "$file" 2>/dev/null
done

log "EKS application setup completed successfully."
