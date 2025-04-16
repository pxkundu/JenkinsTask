#!/bin/bash

# Exit on any error
set -e

# Variables
NAMESPACE="partha-ns-1"
CLUSTER_NAME="partha-cluster-1"
REGION="us-east-1"
SUBNETS="subnet-047677bfebf713139 subnet-0ce1215d1dc5f1bd0"
VPC_ID="vpc-0e13ae6de03f62cd5"

# Step 1: Clean Up Any Existing AWS Load Balancer Controller Resources
echo "Cleaning up existing AWS Load Balancer Controller resources..."
helm uninstall aws-load-balancer-controller -n partha-ns || true
helm uninstall aws-load-balancer-controller -n partha-ns-1 || true
kubectl delete clusterrole aws-load-balancer-controller-role || true
kubectl delete clusterrolebinding aws-load-balancer-controller-rolebinding || true
kubectl delete validatingwebhookconfigurations aws-load-balancer-webhook || true
echo "Cleanup complete."

# Step 2: Check Prerequisites
echo "Checking prerequisites..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if aws cli is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Namespace $NAMESPACE does not exist. Creating it..."
    kubectl create namespace "$NAMESPACE"
fi

# Step 3: Install Helm (if not installed)
echo "Checking Helm installation..."
if ! command -v helm &> /dev/null; then
    echo "Helm not found. Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
else
    echo "Helm is already installed."
fi

# Step 4: Tag Subnets
echo "Tagging subnets for ALB..."
aws ec2 create-tags --resources $SUBNETS --tags Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared || true
echo "Subnets tagged."

# Step 5: Deploy NGINX Application
echo "Deploying NGINX application..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: $NAMESPACE
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.23
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: $NAMESPACE
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF

# Wait for NGINX pod to be ready
echo "Waiting for NGINX pod to be ready..."
kubectl wait --for=condition=ready pod -l app=nginx -n "$NAMESPACE" --timeout=120s

# Step 6: Install AWS Load Balancer Controller
echo "Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts || true
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n "$NAMESPACE" \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION" \
  --set vpcId="$VPC_ID"

# Wait for AWS Load Balancer Controller pods to be ready with a longer timeout
echo "Waiting for AWS Load Balancer Controller pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n "$NAMESPACE" --timeout=300s

# Additional wait to ensure webhook is ready
echo "Waiting an additional 60 seconds to ensure webhook is fully operational..."
sleep 60

# Validation: Check if all controller pods are running
echo "Validating that all AWS Load Balancer Controller pods are running..."
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=aws-load-balancer-controller --field-selector=status.phase=Running -o name | wc -l)
EXPECTED_POD_COUNT=2  # Adjust based on your replica count
if [ "$POD_COUNT" -ne "$EXPECTED_POD_COUNT" ]; then
    echo "Error: Expected $EXPECTED_POD_COUNT AWS Load Balancer Controller pods to be running, but found $POD_COUNT."
    echo "Please check the pod status and logs:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=aws-load-balancer-controller
    kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=aws-load-balancer-controller
    exit 1
fi

echo "Part 1 completed successfully. Run setup-part2.sh to continue."
