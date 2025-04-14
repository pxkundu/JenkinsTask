#!/bin/bash

# k8s-debugger.sh
# Script to collect Kubernetes cluster debugging information, grep for issues, and save to a file

# Set the output file name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="k8s-debug-report-$TIMESTAMP.txt"

# Temporary files to store grep results
TEMP_GREP_FILE=$(mktemp)

# Function to add a section header
add_section() {
    echo "=============================================================" >> "$OUTPUT_FILE"
    echo "[$TIMESTAMP] $1" >> "$OUTPUT_FILE"
    echo "=============================================================" >> "$OUTPUT_FILE"
}

# Function to grep for issues and append to temp file
grep_for_issues() {
    local section="$1"
    local output="$2"
    local patterns=("error" "failed" "NotReady" "CrashLoopBackOff" "cannot resolve pod ENI" "MemoryPressure" "DiskPressure" "NetworkUnavailable" "certificate signed by unknown authority" "ContainerCreating")
    for pattern in "${patterns[@]}"; do
        echo "$output" | grep -i "$pattern" | while read -r line; do
            echo "[$section] $line" >> "$TEMP_GREP_FILE"
        done
    done
}

# Start the report
echo "Kubernetes Cluster Debug Report" > "$OUTPUT_FILE"
echo "Generated at: $TIMESTAMP" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 0. List Contexts (Clusters) in Kubeconfig
add_section "Kubernetes Contexts (Clusters)"
CONTEXTS=$(kubectl config get-contexts 2>&1)
echo "$CONTEXTS" >> "$OUTPUT_FILE"
grep_for_issues "Kubernetes Contexts (Clusters)" "$CONTEXTS"
echo "" >> "$OUTPUT_FILE"

add_section "Kubeconfig Cluster Details"
CLUSTER_DETAILS=$(kubectl config view 2>&1)
echo "$CLUSTER_DETAILS" >> "$OUTPUT_FILE"
grep_for_issues "Kubeconfig Cluster Details" "$CLUSTER_DETAILS"
echo "" >> "$OUTPUT_FILE"

# 1. Cluster Information
add_section "Cluster Information"
CLUSTER_INFO=$(kubectl cluster-info 2>&1)
echo "$CLUSTER_INFO" >> "$OUTPUT_FILE"
grep_for_issues "Cluster Information" "$CLUSTER_INFO"
echo "" >> "$OUTPUT_FILE"

add_section "Node Status"
NODE_STATUS=$(kubectl get nodes -o wide 2>&1)
echo "$NODE_STATUS" >> "$OUTPUT_FILE"
grep_for_issues "Node Status" "$NODE_STATUS"
echo "" >> "$OUTPUT_FILE"

add_section "Node Description (k8s-worker1)"
NODE_DESC=$(kubectl describe node k8s-worker1 2>&1)
echo "$NODE_DESC" >> "$OUTPUT_FILE"
grep_for_issues "Node Description (k8s-worker1)" "$NODE_DESC"
echo "" >> "$OUTPUT_FILE"

# 2. Control Plane Components
add_section "Control Plane Pods (kube-system)"
CONTROL_PODS=$(kubectl get pods -n kube-system -o wide 2>&1)
echo "$CONTROL_PODS" >> "$OUTPUT_FILE"
grep_for_issues "Control Plane Pods (kube-system)" "$CONTROL_PODS"
echo "" >> "$OUTPUT_FILE"

add_section "API Server Logs (kube-apiserver-k8s-master)"
API_LOGS=$(kubectl logs -n kube-system kube-apiserver-k8s-master --tail=50 2>&1)
echo "$API_LOGS" >> "$OUTPUT_FILE"
grep_for_issues "API Server Logs (kube-apiserver-k8s-master)" "$API_LOGS"
echo "" >> "$OUTPUT_FILE"

# 3. Pod Status Across All Namespaces
add_section "All Pods Across Namespaces"
ALL_PODS=$(kubectl get pods -A -o wide 2>&1)
echo "$ALL_PODS" >> "$OUTPUT_FILE"
grep_for_issues "All Pods Across Namespaces" "$ALL_PODS"
echo "" >> "$OUTPUT_FILE"

add_section "Pod Description (todo-app-frontend)"
POD_DESC=$(kubectl describe pod -n todo-app-ns -l app.kubernetes.io/name=todo-app-frontend 2>&1)
echo "$POD_DESC" >> "$OUTPUT_FILE"
grep_for_issues "Pod Description (todo-app-frontend)" "$POD_DESC"
echo "" >> "$OUTPUT_FILE"

# 4. Networking (Flannel)
add_section "Flannel Pods (kube-flannel)"
FLANNEL_PODS=$(kubectl get pods -n kube-flannel -o wide 2>&1)
echo "$FLANNEL_PODS" >> "$OUTPUT_FILE"
grep_for_issues "Flannel Pods (kube-flannel)" "$FLANNEL_PODS"
echo "" >> "$OUTPUT_FILE"

add_section "Flannel Logs (kube-flannel-ds-2sfwx)"
FLANNEL_LOGS=$(kubectl logs -n kube-flannel kube-flannel-ds-2sfwx --tail=50 2>&1)
echo "$FLANNEL_LOGS" >> "$OUTPUT_FILE"
grep_for_issues "Flannel Logs (kube-flannel-ds-2sfwx)" "$FLANNEL_LOGS"
echo "" >> "$OUTPUT_FILE"

# 5. Ingress and Load Balancer
add_section "Ingress (todo-app-ns)"
INGRESS=$(kubectl get ingress -n todo-app-ns -o yaml 2>&1)
echo "$INGRESS" >> "$OUTPUT_FILE"
grep_for_issues "Ingress (todo-app-ns)" "$INGRESS"
echo "" >> "$OUTPUT_FILE"

add_section "AWS Load Balancer Controller Logs"
ALB_LOGS=$(kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50 2>&1)
echo "$ALB_LOGS" >> "$OUTPUT_FILE"
grep_for_issues "AWS Load Balancer Controller Logs" "$ALB_LOGS"
echo "" >> "$OUTPUT_FILE"

# 6. Cluster Events
add_section "Cluster Events (Last 50)"
EVENTS=$(kubectl get events -A --sort-by='.metadata.creationTimestamp' | tail -n 50 2>&1)
echo "$EVENTS" >> "$OUTPUT_FILE"
grep_for_issues "Cluster Events (Last 50)" "$EVENTS"
echo "" >> "$OUTPUT_FILE"

# 7. Resource Usage
add_section "Node Resource Usage"
NODE_USAGE=$(kubectl top nodes 2>&1)
echo "$NODE_USAGE" >> "$OUTPUT_FILE"
grep_for_issues "Node Resource Usage" "$NODE_USAGE"
echo "" >> "$OUTPUT_FILE"

add_section "Pod Resource Usage (todo-app-ns)"
POD_USAGE=$(kubectl top pods -n todo-app-ns 2>&1)
echo "$POD_USAGE" >> "$OUTPUT_FILE"
grep_for_issues "Pod Resource Usage (todo-app-ns)" "$POD_USAGE"
echo "" >> "$OUTPUT_FILE"

# Summary of Potential Issues (Static)
add_section "Summary of Potential Issues (Static Checks)"
echo "1. Control Plane Restarts: Check for high restart counts in kube-system pods (e.g., etcd, kube-apiserver)." >> "$OUTPUT_FILE"
echo "2. Ingress Misconfiguration: Ensure alb.ingress.kubernetes.io/target-type is 'instance', not 'ip'." >> "$OUTPUT_FILE"
echo "3. Flannel Networking: Look for errors in Flannel logs that might affect pod communication." >> "$OUTPUT_FILE"
echo "4. Resource Constraints: Check node and pod resource usage for MemoryPressure or DiskPressure." >> "$OUTPUT_FILE"
echo "5. ALB Target Health: Verify AWS Load Balancer Controller logs for target registration errors." >> "$OUTPUT_FILE"
echo "6. CoreDNS Issues: Check for CoreDNS pods stuck in ContainerCreating, affecting DNS resolution." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Final Findings from Grep
add_section "Final Findings from Grep"
if [ -s "$TEMP_GREP_FILE" ]; then
    echo "The following potential issues were found:" >> "$OUTPUT_FILE"
    cat "$TEMP_GREP_FILE" >> "$OUTPUT_FILE"
else
    echo "No potential issues were found based on the grep patterns." >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Clean up temp file
rm -f "$TEMP_GREP_FILE"

# Notify user
echo "Debug report generated: $OUTPUT_FILE"
