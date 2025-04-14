#!/bin/bash

# Configuration
ARGOCD_SERVER="54.221.131.100:30579"
APP_NAME="todo-app"
NAMESPACE="todo-app-ns"
REPO_URL="https://github.com/pxkundu/JenkinsTask.git"
REPO_PATH="helm/todo-app"
TARGET_REVISION="main"

# ArgoCD CLI login credentials
ARGOCD_USER="admin"
ARGOCD_PASSWORD="5gH40HGgg8UYX1gJ"

# Function to log in to ArgoCD
argocd_login() {
    echo "Logging in to ArgoCD server at $ARGOCD_SERVER..."
    argocd login "$ARGOCD_SERVER" --username "$ARGOCD_USER" --password "$ARGOCD_PASSWORD" --insecure
    if [ $? -ne 0 ]; then
        echo "Error: Failed to log in to ArgoCD. Check server address, credentials, or network."
        exit 1
    fi
}

# Function to create the ArgoCD application
create_argocd_app() {
    echo "Creating ArgoCD application '$APP_NAME'..."
    argocd app create "$APP_NAME" \
        --repo "$REPO_URL" \
        --path "$REPO_PATH" \
        --revision "$TARGET_REVISION" \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace "$NAMESPACE" \
        --sync-policy automated \
        --auto-prune \
        --self-heal \
        --server "$ARGOCD_SERVER" \
        --upsert
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ArgoCD application."
        exit 1
    fi
}

# Function to sync the application with retries
sync_app() {
    echo "Syncing application '$APP_NAME' to start deployment..."
    RETRIES=3
    DELAY=10
    for ((i=1; i<=RETRIES; i++)); do
        argocd app sync "$APP_NAME" --server "$ARGOCD_SERVER"
        if [ $? -eq 0 ]; then
            echo "Application synced successfully!"
            return 0
        fi
        echo "Sync attempt $i/$RETRIES failed. Retrying in $DELAY seconds..."
        sleep $DELAY
    done
    echo "Error: Failed to sync application after $RETRIES attempts."
    exit 1
}

# Main execution
echo "Starting ArgoCD application deployment for '$APP_NAME'..."

argocd_login
create_argocd_app
sync_app

echo "Application deployment initiated. Check status with:"
echo "  argocd app get $APP_NAME --server $ARGOCD_SERVER"
echo "Wait a few minutes, then verify the ALB with:"
echo "  kubectl get ingress -n $NAMESPACE"
