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

# Static configuration values
CLUSTER_NAME="partha-game-cluster"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"
APP_IMAGE="public.ecr.aws/l6m2t8p7/docker-2048:latest"

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
  namespace: $APP_NAMESPACE
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

log "Deploying the application..."
retry 3 10 kubectl apply -f "$manifest_file"
log "Application deployed successfully"
rm -f "$manifest_file"

# Step 6: Get Ingress URL
log "Waiting for Ingress to be ready (up to 15 minutes)..."
for i in {1..30}; do # Increased to 15 minutes (30 * 30s)
    INGRESS_URL=$(kubectl get ingress -n "$APP_NAMESPACE" ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$INGRESS_URL" ]; then
        log "Application is accessible at: http://$INGRESS_URL"
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

log "EKS application setup completed successfully."
