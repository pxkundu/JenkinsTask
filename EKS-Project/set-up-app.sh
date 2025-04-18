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
    local output_file=$(mktemp) || { log "ERROR" "Failed to create temp file"; cleanup; }
    TEMP_FILES+=("$output_file")
    log "COMMAND" "$cmd"
    if eval "$cmd" >"$output_file" 2>&1; then
        local response=$(head -n 5 "$output_file" | tr '\n' ' ')
        [[ -z "$response" ]] && response="Command completed successfully (no output)"
        log "RESPONSE" "$response"
        rm -f "$output_file"
        return 0
    else
        log "ERROR" "Command failed. Full output in $output_file"
        cat "$output_file" >&2
        rm -f "$output_file"
        cleanup
    }
}

# Initialize variables
TEMP_FILES=()
WARNING_LOG="warnings.log"
CLUSTER_NAME="partha-game-cluster"
REGION="us-east-1"
VPC_ID="vpc-0e13ae6de03f62cd5"
APP_NAMESPACE="game-2048"
LB_NAMESPACE="kube-system"
APP_IMAGE="public.ecr.aws/l6m2t8p7/docker-2048:latest"
log "INFO" "Initialized variables for cluster $CLUSTER_NAME in region $REGION"

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up resources due to error or warning..."
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
    local cmd_output=$(mktemp) || { log "ERROR" "Failed to create temp file"; cleanup; }
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

# Verify cluster access
log "INFO" "Verifying cluster access..."
if ! retry 3 10 "kubectl get nodes"; then
    log "ERROR" "Cannot access EKS cluster, ensure kubeconfig is set up correctly"
    cleanup
fi
log "INFO" "Cluster access verified"

# Ensure namespaces exist
log "INFO" "Ensuring namespace $APP_NAMESPACE exists..."
if ! kubectl get namespace "$APP_NAMESPACE" >/dev/null 2>&1; then
    run_command "kubectl create namespace \"$APP_NAMESPACE\""
else
    log "INFO" "Namespace $APP_NAMESPACE already exists"
fi
log "INFO" "Namespace $APP_NAMESPACE verified"
log "INFO" "Ensuring namespace $LB_NAMESPACE exists..."
if ! kubectl get namespace "$LB_NAMESPACE" >/dev/null 2>&1; then
    run_command "kubectl create namespace \"$LB_NAMESPACE\""
else
    log "INFO" "Namespace $LB_NAMESPACE already exists"
fi
log "INFO" "Namespace $LB_NAMESPACE verified"

# Install AWS Load Balancer Controller
log "INFO" "Adding AWS Load Balancer Controller Helm repository..."
retry 3 10 "helm repo add eks https://aws.github.io/eks-charts"
retry 3 10 "helm repo update"
log "INFO" "Helm repository added successfully"
log "INFO" "Installing AWS Load Balancer Controller (latest version)..."
helm_output=$(mktemp) || { log "ERROR" "Failed to create temp file"; cleanup; }
TEMP_FILES+=("$helm_output")
retry 5 60 "helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace \"$LB_NAMESPACE\" \
    --set clusterName=\"$CLUSTER_NAME\" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-lb-controller \
    --set region=\"$REGION\" \
    --set vpcId=\"$VPC_ID\" \
    --wait --timeout=15m" 2>"$helm_output"
check_warnings "$helm_output"
chart_version="unknown"
if command -v jq &> /dev/null; then
    chart_version=$(helm list -n "$LB_NAMESPACE" -o json | jq -r '.[] | select(.name=="aws-load-balancer-controller") | .chart' 2>/dev/null || echo "unknown")
else
    log "WARNING" "'jq' is not installed, cannot determine chart version"
fi
controller_version=$(kubectl get deployment -n "$LB_NAMESPACE" aws-load-balancer-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' || echo "unknown")
log "INFO" "AWS Load Balancer Controller installed successfully (Chart: $chart_version, Controller: $controller_version)"
rm -f "$helm_output"

# Verify AWS Load Balancer Controller
log "INFO" "Verifying AWS Load Balancer Controller installation..."
sleep 30
run_command "kubectl get deployment -n \"$LB_NAMESPACE\" aws-load-balancer-controller"
log "INFO" "AWS Load Balancer Controller verified"

# Deploy the application
log "INFO" "Creating application manifest..."
manifest_file=$(mktemp) || { log "ERROR" "Failed to create temp file for manifest"; cleanup; }
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
log "INFO" "Deploying the application..."
retry 3 10 "kubectl apply -f \"$manifest_file\""
log "INFO" "Application deployed successfully"
rm -f "$manifest_file"

# Get Ingress URL
log "INFO" "Waiting for Ingress to be ready (up to 15 minutes)..."
for i in {1..30}; do
    INGRESS_URL=$(kubectl get ingress -n "$APP_NAMESPACE" ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$INGRESS_URL" ]; then
        log "INFO" "Application is accessible at: http://$INGRESS_URL"
        break
    fi
    log "INFO" "Ingress not ready, retrying in 30 seconds..."
    sleep 30
done
if [ -z "$INGRESS_URL" ]; then
    log "ERROR" "Could not retrieve Ingress URL after retries"
    run_command "kubectl describe ingress -n \"$APP_NAMESPACE\" ingress-2048"
    cleanup
fi

# Clean up temporary files
for file in "${TEMP_FILES[@]}"; do
    rm -f "$file" 2>/dev/null
done
log "INFO" "EKS application setup completed successfully."
