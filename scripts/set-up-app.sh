#!/bin/bash

# Do not exit on errors, handle them gracefully
set +e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to retry a command
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1
    while [ $attempt -le "$max_attempts" ]; do
        log "Attempt $attempt of $max_attempts: $@"
        if "$@"; then
            return 0
        fi
        log "WARNING: Command failed, retrying in $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
    log "ERROR: Command failed after $max_attempts attempts: $@"
    return 1
}

# Configuration variables
CLUSTER_NAME="fargate-cluster-partha"
REGION="us-east-1"
NAMESPACE="aws-load-balancer-controller"
VPC_ID="vpc-0e13ae6de03f62cd5"

# Step 1: Verify cluster access
log "Verifying cluster access..."
if ! kubectl get nodes &> /dev/null; then
    log "WARNING: Cannot access EKS cluster, ensure kubeconfig is set up correctly"
else
    log "Cluster access verified"
fi

# Step 2: Install AWS Load Balancer Controller using Helm
log "Adding AWS Load Balancer Controller Helm repository..."
retry 3 10 helm repo add eks https://aws.github.io/eks-charts && helm repo update && log "Helm repository added successfully" || {
    log "WARNING: Failed to add Helm repository, proceeding anyway"
}

log "Installing AWS Load Balancer Controller..."
retry 3 30 helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace "$NAMESPACE" \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="$REGION" \
    --set vpcId="$VPC_ID" \
    --wait --timeout=10m && log "AWS Load Balancer Controller installed successfully" || {
        log "WARNING: Failed to install AWS Load Balancer Controller, proceeding anyway"
    }

# Step 3: Verify installation
log "Verifying AWS Load Balancer Controller installation..."
sleep 30 # Wait for resources to stabilize
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || log "WARNING: Failed to get pods"
kubectl get services -n "$NAMESPACE" -o wide 2>/dev/null || log "WARNING: Failed to get services"

# Step 4: Deploy test application
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
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
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

# Step 5: Get Ingress URL
log "Waiting for Ingress to be ready..."
for i in {1..10}; do
    INGRESS_URL=$(kubectl get ingress -n "$NAMESPACE" test-app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$INGRESS_URL" ]; then
        log "AWS Load Balancer Controller Ingress is accessible at: http://$INGRESS_URL"
        break
    fi
    log "Ingress not ready, retrying in 30 seconds..."
    sleep 30
done
if [ -z "$INGRESS_URL" ]; then
    log "WARNING: Could not retrieve Ingress URL after retries"
fi

log "EKS application setup with AWS Load Balancer Controller completed. Check warnings for any issues."
