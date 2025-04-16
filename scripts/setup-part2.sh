#!/bin/bash

# Exit on any error
set -e

# Variables
NAMESPACE="partha-ns-1"

# Step 1: Validate AWS Load Balancer Controller Pods
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

# Step 2: Create Ingress for NGINX with Retry Logic
echo "Creating Ingress for NGINX..."
for attempt in {1..3}; do
    if cat <<EOF | kubectl apply -f - 2>/tmp/ingress-error.log; then
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: $NAMESPACE
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
            name: nginx
            port:
              number: 80
EOF
        echo "Ingress created successfully."
        break
    else
        if grep -q "failed calling webhook" /tmp/ingress-error.log; then
            echo "Webhook failed. Deleting ValidatingWebhookConfiguration and retrying (attempt $attempt/3)..."
            kubectl delete validatingwebhookconfigurations aws-load-balancer-webhook || true
            sleep 10
        else
            echo "Failed to create Ingress for unknown reason:"
            cat /tmp/ingress-error.log
            exit 1
        fi
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "Error: Failed to create Ingress after 3 attempts due to webhook issues."
        exit 1
    fi
done

# Step 3: Wait for Ingress ADDRESS
echo "Waiting for Ingress to get an ADDRESS..."
for i in {1..30}; do
    ADDRESS=$(kubectl get ingress nginx-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true)
    if [ -n "$ADDRESS" ]; then
        echo "Ingress ADDRESS: $ADDRESS"
        break
    fi
    echo "Waiting for Ingress ADDRESS... ($i/30)"
    sleep 30
done

if [ -z "$ADDRESS" ]; then
    echo "Error: Ingress did not get an ADDRESS within 15 minutes."
    exit 1
fi

# Step 4: Test NGINX Access
echo "Testing NGINX access..."
curl -s --connect-timeout 10 "http://$ADDRESS" | grep "Welcome to nginx!" || {
    echo "Error: Failed to access NGINX at http://$ADDRESS"
    exit 1
}

echo "Deployment successful! NGINX is accessible at http://$ADDRESS"
