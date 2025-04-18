
# README: EKS Cluster Setup and Application Deployment

This `README.md` guides you through setting up an AWS Elastic Kubernetes Service (EKS) cluster with Fargate and deploying the 2048 game via an Application Load Balancer (ALB) using two scripts: `set-up-infra.sh` and `set-up-app.sh`. Designed for developers and DevOps engineers, it ensures a secure, scalable Kubernetes environment with clear steps for collaboration and troubleshooting.

## Overview

- **Scripts**:
  - `set-up-infra.sh`: Creates the EKS cluster, Fargate profiles, IAM roles, and AWS Load Balancer Controller prerequisites.
  - `set-up-app.sh`: Deploys the AWS Load Balancer Controller and the 2048 game with public Ingress.
- **Purpose**: Automate a consistent, production-ready Kubernetes setup and application deployment.
- **Environment**: AWS EKS with Fargate, using hardcoded values for a specific AWS account.
- **Hardcoded Values**:
  - Cluster Name: `partha-game-cluster`
  - Region: `us-east-1`
  - VPC ID: `vpc-0e13ae6de03f62cd5`
  - Private Subnets: `subnet-07b231970a5ea0a3a,subnet-066008bd872659833`
  - Kubernetes Version: `1.32`
  - Application Namespace: `game-2048`
  - Load Balancer Namespace: `kube-system`
  - Container Image: `public.ecr.aws/l6m2t8p7/docker-2048:latest`

## Step 1: Verify Prerequisites

Before running the scripts, confirm the following to avoid failures:

1. **AWS Credentials**:

   ```bash
   aws sts get-caller-identity
   ```

   **Expected Response**:

   ```
   {
       "UserId": "AIDAXYZ1234567890",
       "Account": "123456789012",
       "Arn": "arn:aws:iam::123456789012:user/your-user"
   }
   ```

   - **Fix**: Run `aws configure` if credentials are missing or invalid.

2. **IAM Permissions**:

   - Ensure your IAM user/role has permissions for EKS, IAM, EC2, ELB, and CloudFormation.
   - Check policy:

     ```bash
     aws iam get-policy --policy-arn arn:aws:iam::123456789012:policy/your-policy
     ```

     **Expected Response**: Includes `eks:*`, `iam:*`, etc.

3. **VPC and Subnets**:

   ```bash
   aws ec2 describe-vpcs --vpc-ids vpc-0e13ae6de03f62cd5 --region us-east-1
   ```

   **Expected Response**:

   ```
   {
       "Vpcs": [
           {
               "VpcId": "vpc-0e13ae6de03f62cd5",
               "State": "available",
               ...
           }
       ]
   }
   ```

   - Verify subnets:

     ```bash
     aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0e13ae6de03f62cd5" --region us-east-1
     ```

     **Expected Response**: Includes `subnet-07b231970a5ea0a3a`, `subnet-066008bd872659833`.

4. **DNS Settings**:

   ```bash
   aws ec2 describe-vpc-attribute --vpc-id vpc-0e13ae6de03f62cd5 --attribute enableDnsHostnames --region us-east-1
   aws ec2 describe-vpc-attribute --vpc-id vpc-0e13ae6de03f62cd5 --attribute enableDnsSupport --region us-east-1
   ```

   **Expected Response**:

   ```
   {"VpcId": "vpc-0e13ae6de03f62cd5", "EnableDnsHostnames": {"Value": true}}
   {"VpcId": "vpc-0e13ae6de03f62cd5", "EnableDnsSupport": {"Value": true}}
   ```

   - **Fix**:

     ```bash
     aws ec2 modify-vpc-attribute --vpc-id vpc-0e13ae6de03f62cd5 --enable-dns-hostnames
     aws ec2 modify-vpc-attribute --vpc-id vpc-0e13ae6de03f62cd5 --enable-dns-support
     ```

5. **Tools Installed**:

   ```bash
   aws --version
   eksctl version
   kubectl version --client
   helm version
   ```

   **Expected Response**:

   ```
   aws-cli/2.15.30 Python/3.11.8 Linux/5.15.0-73-generic
   0.185.0
   Client Version: v1.32.0
   version.BuildInfo{Version:"v3.16.2", ...}
   ```

   - **Fix**: Install missing tools as shown in “Install Tools” below.

6. **Internet Access**:

   ```bash
   ping -c 4 google.com
   ```

   **Expected Response**:

   ```
   PING google.com (142.250.190.78) 56(84) bytes of data.
   64 bytes from 142.250.190.78: icmp_seq=1 ttl=117 time=10.2 ms
   ...
   ```

**Why This Matters**:

- Verifying prerequisites ensures the scripts run without errors due to missing permissions, network misconfigurations, or absent tools, saving time and resources.

## Step 2: Retrieve Private Subnets for the VPC

The scripts use private subnets (`subnet-07b231970a5ea0a3a,subnet-066008bd872659833`) in `vpc-0e13ae6de03f62cd5`. Private subnets lack a direct route to an Internet Gateway and use a NAT Gateway for outbound traffic.

1. **List Subnets**:

   ```bash
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0e13ae6de03f62cd5" --region us-east-1 --query 'Subnets[*].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,CidrBlock:CidrBlock}' --output table
   ```

   **Example Response**:

   ```
   -----------------------------------------------------------------------------------
   |                                 DescribeSubnets                                  |
   +-----------------+--------------------------+------------------------------------+
   | AvailabilityZone| CidrBlock                | SubnetId                           |
   +-----------------+--------------------------+------------------------------------+
   | us-east-1a      | 10.0.1.0/24             | subnet-07b231970a5ea0a3a           |
   | us-east-1b      | 10.0.2.0/24             | subnet-066008bd872659833           |
   | us-east-1c      | 10.0.3.0/24             | subnet-0a1b2c3d4e5f6a7b8           |
   +-----------------+--------------------------+------------------------------------+
   ```

2. **Confirm Private Subnets**:

   ```bash
   aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-07b231970a5ea0a3a" --region us-east-1 --query 'RouteTables[*].Routes' --output json
   ```

   **Example Response**:

   ```json
   [
     [
       {
         "DestinationCidrBlock": "10.0.0.0/16",
         "GatewayId": "local",
         "State": "active"
       },
       {
         "DestinationCidrBlock": "0.0.0.0/0",
         "NatGatewayId": "nat-0a1b2c3d4e5f6a7b8",
         "State": "active"
       }
     ]
   ]
   ```

   - **Note**: No `GatewayId` with `igw-` confirms a private subnet. Repeat for other subnets.

3. **Select Subnets**:

   - Use at least two private subnets in different Availability Zones (e.g., `us-east-1a`, `us-east-1b`).
   - Update `PRIVATE_SUBNETS` in `set-up-infra.sh` if needed.

**Why This Matters**:

- EKS with Fargate requires private subnets for pod networking, and a NAT Gateway enables image pulls, preventing network-related failures.

## Step 3: Set Up Team Access to the Cluster

To enable collaboration, configure access for team members to manage `partha-game-cluster`.

1. **Grant IAM Permissions**:

   ```bash
   eksctl create iamidentitymapping \
     --cluster partha-game-cluster \
     --region us-east-1 \
     --arn arn:aws:iam::123456789012:user/team-member \
     --group system:masters \
     --no-duplicate-arns
   ```

   **Example Response**:

   ```
   2025-04-18 06:30:00 [ℹ]  added IAM identity mapping
   ```

   - **Note**: Replace the ARN with the team member’s IAM user/role. Use `system:masters` for admin access or custom RBAC for restrictions.

2. **Share Kubeconfig**:

   - Team members run:

     ```bash
     aws eks update-kubeconfig --name partha-game-cluster --region us-east-1
     ```

     **Example Response**:

     ```
     Added new context arn:aws:eks:us-east-1:123456789012:cluster/partha-game-cluster to /home/user/.kube/config
     ```

   - Ensure their AWS CLI has valid credentials.

3. **Optional RBAC for Restricted Access**:

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     namespace: game-2048
     name: dev-access
   rules:
   - apiGroups: [""]
     resources: ["pods", "services"]
     verbs: ["get", "list", "watch"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     namespace: game-2048
     name: dev-access-binding
   subjects:
   - kind: User
     name: team-member@example.com
     apiGroup: rbac.authorization.k8s.io
   roleRef:
     kind: Role
     name: dev-access
     apiGroup: rbac.authorization.k8s.io
   EOF
   ```

   **Example Response**:

   ```
   role.rbac.authorization.k8s.io/dev-access created
   rolebinding.rbac.authorization.k8s.io/dev-access-binding created
   ```

4. **Best Practices**:

   - Prefer IAM roles over users.
   - Use RBAC for least privilege (e.g., read-only access).
   - Rotate credentials regularly or use AWS SSO.

**Why This Matters**:

- Team access fosters collaboration while IAM and RBAC maintain security and auditability.

## Step 4: Install Tools (set-up-infra.sh)

Install required tools if not already present (verified in Step 1).

**Commands** (from `set-up-infra.sh`):

```bash
check_and_install_command "aws" "
    curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' &&
    unzip awscliv2.zip &&
    sudo ./aws/install &&
    rm -rf awscliv2.zip aws
"
check_and_install_command "eksctl" "
    curl --silent --location 'https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz' | tar xz -C /tmp &&
    sudo mv /tmp/eksctl /usr/local/bin
"
check_and_install_command "kubectl" "
    curl -LO 'https://dl.k8s.io/release/v1.32/bin/linux/amd64/kubectl' &&
    chmod +x kubectl &&
    sudo mv kubectl /usr/local/bin/
"
check_and_install_command "helm" "
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"
```

**What Happens**:

- Installs `aws`, `eksctl`, `kubectl`, and `helm` based on the OS (Linux, macOS, or Windows).

**Example Response**:

```
[2025-04-18 06:30:01] aws is already installed
[2025-04-18 06:30:01] eksctl is already installed
[2025-04-18 06:30:01] kubectl is already installed
[2025-04-18 06:30:01] helm is already installed
```

## Step 5: Create EKS Cluster (set-up-infra.sh)

Provision the EKS cluster and related resources.

1. **Initialize Environment**:

   ```bash
   #!/bin/bash
   set -e
   log() {
       echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
   }
   ```

   **What Happens**: Configures Bash to exit on errors and logs with timestamps.

2. **Define Variables**:

   ```bash
   CLUSTER_NAME="partha-game-cluster"
   REGION="us-east-1"
   VPC_ID="vpc-0e13ae6de03f62cd5"
   PRIVATE_SUBNETS="subnet-07b231970a5ea0a3a,subnet-066008bd872659833"
   K8S_VERSION="1.32"
   APP_NAMESPACE="game-2048"
   LB_NAMESPACE="kube-system"
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   TIMESTAMP=$(date +%s)
   IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-$TIMESTAMP"
   ```

   **Example Response**:

   ```
   [2025-04-18 06:30:00] Running command: aws sts get-caller-identity ...
   ACCOUNT_ID=123456789012
   ```

3. **Create Cluster**:

   ```bash
   eksctl create cluster \
       --name "$CLUSTER_NAME" \
       --region "$REGION" \
       --fargate \
       --vpc-private-subnets="$PRIVATE_SUBNETS" \
       --version "$K8S_VERSION" \
       --without-nodegroup
   ```

   **Example Response**:

   ```
   [2025-04-18 06:30:03] Creating EKS cluster: partha-game-cluster with Kubernetes version 1.32 in region us-east-1
   [2025-04-18 06:50:03] EKS cluster created successfully
   ```

4. **Enable OIDC Provider**:

   ```bash
   eksctl utils associate-iam-oidc-provider --region="$REGION" --cluster="$CLUSTER_NAME" --approve
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:04] Enabling IAM OIDC provider...
   [2025-04-18 06:50:05] IAM OIDC provider enabled successfully
   ```

5. **Add Default Addons**:

   ```bash
   eksctl create addon --cluster "$CLUSTER_NAME" --region "$REGION" --name vpc-cni --version latest
   eksctl create addon --cluster "$CLUSTER_NAME" --region "$REGION" --name metrics-server --version latest
   eksctl create addon --cluster "$CLUSTER_NAME" --region "$REGION" --name kube-proxy --version latest
   eksctl create addon --cluster "$CLUSTER_NAME" --region "$REGION" --name coredns --version latest
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:06] Successfully created addon: vpc-cni
   [2025-04-18 06:50:08] Successfully created addon: metrics-server
   [2025-04-18 06:50:09] Successfully created addon: kube-proxy
   [2025-04-18 06:50:10] Successfully created addon: coredns
   ```

6. **Create Namespaces**:

   ```bash
   kubectl create namespace "$APP_NAMESPACE" || echo "Namespace $APP_NAMESPACE already exists"
   kubectl create namespace "$LB_NAMESPACE" || echo "Namespace $LB_NAMESPACE already exists"
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:11] namespace/game-2048 created
   [2025-04-18 06:50:16] Namespace kube-system already exists
   ```

7. **Create Fargate Profiles**:

   ```bash
   eksctl create fargateprofile --cluster "$CLUSTER_NAME" --region "$REGION" --name "app-profile" --namespace "$APP_NAMESPACE"
   eksctl create fargateprofile --cluster "$CLUSTER_NAME" --region "$REGION" --name "lb-profile" --namespace "$LB_NAMESPACE"
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:13] Fargate profile created successfully
   [2025-04-18 06:50:15] Fargate profile for kube-system created successfully
   ```

8. **Create IAM Policy**:

   ```bash
   aws iam create-policy --policy-name "$IAM_POLICY_NAME" --policy-document file://aws-lb-controller-policy.json
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:18] IAM policy created successfully with ARN: arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy-1747638600
   ```

9. **Create IAM Service Account**:

   ```bash
   eksctl create iamserviceaccount \
       --cluster "$CLUSTER_NAME" \
       --namespace "$LB_NAMESPACE" \
       --name "aws-lb-controller" \
       --role-name "EKSLoadBalancerControllerRole" \
       --attach-policy-arn "$IAM_POLICY_ARN" \
       --approve \
       --region "$REGION" \
       --override-existing-serviceaccounts
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:20] IAM service account created successfully
   ```

**Why This Matters**:

- This step sets up the EKS cluster, Fargate profiles, and IAM configurations, providing the foundation for application deployment.

## Step 6: Deploy the Application (set-up-app.sh)

Deploy the AWS Load Balancer Controller and 2048 game.

1. **Initialize Environment**:

   ```bash
   #!/bin/bash
   set -e
   log() {
       echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
   }
   ```

   **What Happens**: Configures Bash and logging.

2. **Define Variables**:

   ```bash
   CLUSTER_NAME="partha-game-cluster"
   REGION="us-east-1"
   VPC_ID="vpc-0e13ae6de03f62cd5"
   APP_NAMESPACE="game-2048"
   LB_NAMESPACE="kube-system"
   APP_IMAGE="public.ecr.aws/l6m2t8p7/docker-2048:latest"
   ```

3. **Verify Cluster Access**:

   ```bash
   kubectl get nodes
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:22] NAME                            STATUS   ROLES    AGE    VERSION
   fargate-ip-10-0-1-100.ec2...   Ready    <none>   10m    v1.32.0-eks-...
   ```

4. **Install Load Balancer Controller**:

   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
       --namespace "$LB_NAMESPACE" \
       --set clusterName="$CLUSTER_NAME" \
       --set serviceAccount.create=false \
       --set serviceAccount.name=aws-lb-controller \
       --set region="$REGION" \
       --set vpcId="$VPC_ID" \
       --wait --timeout=15m
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:25] AWS Load Balancer Controller installed successfully (Chart: aws-load-balancer-controller-1.7.2, Controller: v2.7.0)
   ```

5. **Verify Controller**:

   ```bash
   kubectl get deployment -n "$LB_NAMESPACE" aws-load-balancer-controller
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:56] NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
   aws-load-balancer-controller   1/1     1            1           30s
   ```

6. **Deploy 2048 Game**:

   ```bash
   kubectl apply -f manifest.yaml
   ```

   **Example Response**:

   ```
   [2025-04-18 06:50:57] namespace/game-2048 unchanged
   deployment.apps/deployment-2048 created
   service/service-2048 created
   ingress.networking.k8s.io/ingress-2048 created
   ```

7. **Get Ingress URL**:

   ```bash
   kubectl get ingress -n "$APP_NAMESPACE" ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

   **Example Response**:

   ```
   [2025-04-18 06:51:58] Application is accessible at: http://k8s-game2048-ingress2-ff4d192d60-1096844032.us-east-1.elb.amazonaws.com
   ```

**Why This Matters**:

- Deploys the application and exposes it publicly, completing the setup.

## Step 7: Access the Cluster

The scripts use `kubectl` for cluster interaction.

1. **Kubeconfig Setup**:

   - `set-up-infra.sh` updates `~/.kube/config`:

     ```bash
     aws eks update-kubeconfig --name partha-game-cluster --region us-east-1
     ```

     **Example Response**:

     ```
     Added new context arn:aws:eks:us-east-1:123456789012:cluster/partha-game-cluster to /home/user/.kube/config
     ```

2. **Run Commands**:

   - `kubectl` authenticates using AWS CLI credentials.
   - Example:

     ```bash
     kubectl get pods -n game-2048
     ```

     **Example Response**:

     ```
     NAME                            READY   STATUS    RESTARTS   AGE
     deployment-2048-abc123-xyz      1/1     Running   0          5m
     ```

**Why This Matters**:

- Ensures you and your team can manage the cluster effectively.

## Step 8: Run the Scripts

1. **Save and Make Executable**:

   ```bash
   chmod +x set-up-infra.sh set-up-app.sh
   ```

2. **Run Infrastructure Setup** (~20-30 minutes):

   ```bash
   ./set-up-infra.sh
   ```

3. **Run Application Deployment** (~5-15 minutes):

   ```bash
   ./set-up-app.sh
   ```

4. **Verify**:

   ```bash
   aws eks describe-cluster --name partha-game-cluster --region us-east-1
   kubectl get deployment -n game-2048 deployment-2048
   curl http://<ingress-url>
   ```

## Troubleshooting

- **Credential Errors**:

  ```bash
  aws configure
  ```

- **Subnet Issues**:

  - Reverify subnets (Step 2).

- **Cluster Access**:

  ```bash
  aws eks update-kubeconfig --name partha-game-cluster --region us-east-1
  ```

- **Ingress Not Ready**:

  ```bash
  kubectl describe ingress -n game-2048 ingress-2048
  ```

- **Manual Cleanup**:

  ```bash
  eksctl delete cluster --name partha-game-cluster --region us-east-1
  aws iam delete-policy --policy-arn arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy-<timestamp>
  aws iam delete-role --role-name EKSLoadBalancerControllerRole
  ```

## Enhancing the Setup

To improve usability and robustness:

1. **Architecture Diagram**:
   - Add a visual of the VPC, subnets, EKS cluster, Fargate pods, and ALB.

2. **Troubleshooting Guide**:
   - Document errors like `AccessDenied` with fixes.

3. **Environment Variables**:

   ```bash
   export CLUSTER_NAME="partha-game-cluster"
   export REGION="us-east-1"
   ```

   - Source in scripts for flexibility.

4. **Monitoring**:

   ```bash
   aws eks update-cluster-config --name partha-game-cluster --region us-east-1 --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
   ```

   - Check logs in CloudWatch.

5. **Security**:
   - Use VPC endpoints for EKS/S3.
   - Encrypt secrets with AWS KMS.

6. **Testing**:

   ```bash
   curl http://<ingress-url>
   ```

7. **CI/CD**:
   - Integrate with Jenkins or GitHub Actions, leveraging your interest in Jenkins pipelines (March 2025).

8. **Rollback**:

   ```bash
   kubectl delete -f manifest.yaml
   helm uninstall aws-load-balancer-controller -n kube-system
   ```

9. **Version Control**:
   - Use a Git changelog.

10. **FAQ**:
    - Address questions like “Can I change the image?” or “How to scale?”

**Prepared by**: Partha Sarathi Kundu [github/pxkundu]
**Date**: April 18, 2025

---

