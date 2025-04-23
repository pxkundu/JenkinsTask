# Ansible Setup for EKS and Kubernetes Management

This directory (`partha-ansible/`) contains Ansible configuration files, playbooks, and scripts to manage a Kubernetes worker node (`k8-worker-partha`, private IP `172.31.36.219`) in an Amazon EKS cluster hosted on AWS EC2 instances. The setup automates configuration management, application deployment, security hardening, and monitoring tasks, running from the control plane node (`jenkins-k8-master`, `t2.medium`, Amazon Linux 2023) using passwordless SSH with a custom key (`id_rsa_partha`).

## Purpose

The Ansible setup automates critical tasks for managing an EKS cluster, including:

- Configuring worker nodes with utilities and scripts.
- Deploying applications to EKS using Helm.
- Managing logs with rotation and CloudWatch integration.
- Securing node access with IAM Roles for Service Accounts (IRSA).
- Hardening node security for compliance.
- Configuring autoscaling for EKS node groups.

This enables efficient, repeatable automation for Kubernetes and AWS environments, supporting DevSecOps workflows in a Fortune 100-like setup.

## Prerequisites

Before setting up and running the playbooks, ensure the following:

- **EC2 Instances**:
  - `jenkins-k8-master` (t2.medium, Amazon Linux 2023): Kubernetes control plane with `kubectl`, AWS CLI, and Ansible installed.
  - `k8-worker-partha` (t2.micro, Amazon Linux 2023, private IP `172.31.36.219`): EKS worker node.
- **EKS Cluster**:
  - An active EKS cluster (e.g., `my-eks-cluster`) with `k8-worker-partha` joined (`kubectl get nodes` shows `Ready`).
  - OIDC provider enabled for IRSA (`aws eks describe-cluster --name my-eks-cluster`).
- **Ansible**:
  - Installed on `jenkins-k8-master`: `sudo yum install -y epel-release ansible`.
  - Ansible collection for AWS: `ansible-galaxy collection install amazon.aws`.
- **SSH Configuration**:
  - Private key: `/home/ec2-user/.ssh/id_rsa_partha` on `jenkins-k8-master`.
  - Public key: In `/home/ec2-user/.ssh/authorized_keys` on `k8-worker-partha`.
  - SSH config: `/home/ec2-user/.ssh/config` with:

    ```
    Host 172.31.36.219
        HostName 172.31.36.219
        User ec2-user
        IdentityFile /home/ec2-user/.ssh/id_rsa_partha
    ```
  - Permissions: `chmod 600 ~/.ssh/config ~/.ssh/id_rsa_partha; chmod 644 ~/.ssh/id_rsa_partha.pub`.
- **AWS Credentials**:
  - AWS CLI configured on `jenkins-k8-master` with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and region (`us-east-1`).
  - IAM roles for:
    - CloudWatch: `CloudWatchLogsFullAccess` for `k8-worker-partha`.
    - EKS: `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`.
    - IRSA: Custom S3 access policy and role.
- **Security Group**:
  - `k8s-worker-sg` allows SSH (port 22) from `jenkins-k8-master`’s private IP (e.g., `172.31.1.76/32`) and Kubernetes ports (e.g., 10250, 443).
- **Git Repository**:
  - Clone `jenkins-terraform-k8s-worker` to `~/jenkins-terraform-k8s-worker` for version control.
- **Additional Tools**:
  - `boto3` for dynamic inventory: `sudo pip3 install boto3`.
  - `kubectl` and `helm` on `jenkins-k8-master` for Kubernetes tasks.

## Directory Structure

```
partha-ansible/
├── inventory/
│   ├── hosts.ini               # Static inventory for k8-worker-partha
│   └── aws_ec2.yml            # Dynamic AWS EC2 inventory
├── playbook/
│   ├── site.yml               # Installs tree and verifies
│   ├── configure_k8s_worker.yml # Installs jq, deploys script, labels node
│   ├── install_kube_tools.yml  # Installs kubectl and helm
│   ├── monitor_node.yml       # Monitors node health
│   ├── deploy_helm_app.yml    # Deploys Nginx via Helm to EKS
│   ├── configure_log_rotation.yml # Configures log rotation and CloudWatch
│   ├── configure_irsa.yml     # Sets up IRSA for S3 access
│   ├── harden_eks_node.yml    # Hardens node security
│   ├── configure_eks_autoscaling.yml # Configures EKS node group autoscaling
├── scripts/
│   └── setup_ssh_passwordless.sh # Sets up passwordless SSH
├── ansible.cfg                # Ansible configuration
└── README.md                 # This file
```

## Playbooks

Below is a detailed description of each playbook, its purpose, tasks, and how it works.

### 1. site.yml

- **Purpose**: Performs basic configuration and verification of the worker node, ensuring connectivity and installing a utility package (`tree`).
- **Tasks**:
  - Pings the node to verify SSH connectivity.
  - Installs the `tree` package using `yum`.
  - Verifies the `tree` version and displays it.
- **How It Works**:
  - Uses the `ansible.builtin.ping` module to test SSH access.
  - Installs `tree` idempotently with `ansible.builtin.yum`.
  - Runs `tree --version` and outputs the result for verification.
- **Use Case**: Initial setup and connectivity testing for new nodes, common in Fortune 100 environments for baseline configuration.

### 2. configure_k8s_worker.yml

- **Purpose**: Configures the EKS worker node with utilities, scripts, and Kubernetes labels for workload organization.
- **Tasks**:
  - Installs `jq` for JSON processing.
  - Deploys a script (`check_node.sh`) to `/usr/local/bin/` to check node status.
  - Labels the node with `app=worker` using `kubectl`.
  - Verifies `jq`, script presence, and node labels.
- **How It Works**:
  - Uses `ansible.builtin.yum` to install `jq` and `ansible.builtin.copy` for the script.
  - Delegates `kubectl` tasks to `localhost` (`jenkins-k8-master`) for Kubernetes API access.
  - Ensures idempotency and verifies outcomes with `ansible.builtin.command` and `ansible.builtin.stat`.
- **Use Case**: Prepares nodes for specific workloads, aligning with your Kubernetes setup (April 7, 2025).

### 3. install_kube_tools.yml

- **Purpose**: Installs Kubernetes tools (`kubectl`, `helm`) on the worker node for local debugging and scripting.
- **Tasks**:
  - Downloads and installs `kubectl` from the Kubernetes release.
  - Installs `helm` using the official script.
  - Verifies versions of both tools.
- **How It Works**:
  - Uses `ansible.builtin.shell` with `creates` to ensure idempotent installation.
  - Runs verification commands (`kubectl version --client`, `helm version`) and displays outputs.
- **Use Case**: Enables advanced Kubernetes tasks on worker nodes, useful for debugging in hybrid environments.

### 4. monitor_node.yml

- **Purpose**: Monitors the worker node’s health (CPU, memory, disk) and Kubernetes status, logging results for observability.
- **Tasks**:
  - Installs `sysstat` for system metrics.
  - Collects CPU, memory, and disk usage metrics.
  - Checks node status with `kubectl`.
  - Logs results to `/var/log/node_health.log` and fetches the log to `jenkins-k8-master`.
- **How It Works**:
  - Uses `ansible.builtin.shell` for metrics collection and `ansible.builtin.command` for `kubectl`.
  - Appends results to a log file with `ansible.builtin.lineinfile` and retrieves it with `ansible.builtin.fetch`.
- **Use Case**: Ongoing health monitoring, aligning with your DevSecOps monitoring interest (April 22, 2025).

### 5. deploy_helm_app.yml

- **Purpose**: Deploys an Nginx application to the EKS cluster using Helm, automating microservice deployments.
- **Tasks**:
  - Installs Helm on the worker node.
  - Adds the Bitnami Helm repository.
  - Deploys the Nginx chart to the `default` namespace.
  - Verifies pod deployment with `kubectl`.
- **How It Works**:
  - Uses `ansible.builtin.shell` for Helm installation and `ansible.builtin.command` for repository and deployment tasks.
  - Delegates Helm and `kubectl` commands to `localhost` for EKS API access.
  - Ensures idempotency with Helm’s `upgrade --install`.
- **Use Case**: Rapid, repeatable application deployments, common in e-commerce (e.g., Walmart).

### 6. configure_log_rotation.yml

- **Purpose**: Configures log rotation for application logs and integrates with AWS CloudWatch for centralized monitoring.
- **Tasks**:
  - Installs `logrotate` and configures it for `/var/log/app/*.log`.
  - Installs the CloudWatch Logs agent.
  - Configures the agent to send logs to CloudWatch.
  - Verifies log rotation configuration.
- **How It Works**:
  - Uses `ansible.builtin.yum` for `logrotate` and `ansible.builtin.shell` for the CloudWatch agent.
  - Configures log rotation with `ansible.builtin.copy` and CloudWatch with a custom configuration file.
- **Use Case**: Ensures disk space management and observability, critical for compliance (e.g., Bank of America).

### 7. configure_irsa.yml

- **Purpose**: Sets up IAM Roles for Service Accounts (IRSA) to grant EKS pods secure access to AWS services (e.g., S3).
- **Tasks**:
  - Creates an IAM policy and role for S3 access.
  - Associates the role with a Kubernetes service account (`s3-access-sa`).
  - Deploys a test pod with the service account.
  - Verifies S3 access from the pod.
- **How It Works**:
  - Uses `ansible.builtin.command` with AWS CLI to create IAM resources and `kubectl` for Kubernetes tasks.
  - Runs on `localhost` to leverage AWS CLI and `kubectl` configurations.
  - Ensures secure pod access without hardcoded credentials.
- **Use Case**: Enhances security for EKS workloads, aligning with your IRSA interest (April 21, 2025).

### 8. harden_eks_node.yml

- **Purpose**: Hardens EKS worker node security by disabling root SSH, enabling SELinux, and configuring a firewall.
- **Tasks**:
  - Disables root SSH login and password authentication.
  - Enables SELinux in enforcing mode.
  - Installs and configures `firewalld` to allow SSH.
  - Verifies SSH configuration.
- **How It Works**:
  - Uses `ansible.builtin.lineinfile` for SSH and SELinux configurations, `ansible.builtin.yum` for `firewalld`, and `ansible.builtin.service` for service management.
  - Includes handlers to restart services (`sshd`, `firewalld`) on changes.
- **Use Case**: Ensures CIS compliance, critical for regulated industries (e.g., JPMorgan Chase).

### 9. configure_eks_autoscaling.yml

- **Purpose**: Configures EKS node group autoscaling to handle workload fluctuations efficiently.
- **Tasks**:
  - Installs AWS CLI on the control node.
  - Creates an EKS node group with autoscaling settings.
  - Deploys the Cluster Autoscaler to manage node scaling.
  - Verifies node group status.
- **How It Works**:
  - Uses `ansible.builtin.shell` for AWS CLI installation and `ansible.builtin.command` for EKS and `kubectl` tasks.
  - Runs on `localhost` to interact with AWS and EKS APIs.
  - Configures autoscaling with min/max/desired sizes.
- **Use Case**: Optimizes resource usage, common in e-commerce (e.g., Amazon).

## Setup Instructions

1. **Clone Repository**:

   ```bash
   cd ~
   git clone <repository-url> jenkins-terraform-k8s-worker
   ```

2. **Copy Ansible Files**:

   ```bash
   mkdir -p ~/partha-ansible/{inventory,playbook,scripts}
   cp -r ~/jenkins-terraform-k8s-worker/partha-ansible/* ~/partha-ansible/
   cd ~/partha-ansible
   chmod 644 inventory/* playbook/* ansible.cfg
   chmod +x scripts/setup_ssh_passwordless.sh
   ```

3. **Configure ansible.cfg**:

   - Ensure `ansible.cfg` includes:

     ```
     [defaults]
     inventory = ./inventory/hosts.ini,./inventory/aws_ec2.yml
     log_path = ~/ansible/ansible.log
     host_key_checking = False
     timeout = 30
     [ssh_connection]
     ssh_args = -o ControlMaster=auto -o ControlPersist=60s
     ```

4. **Verify SSH**:

   ```bash
   ssh ec2-user@172.31.36.219
   ```

   - If it fails, run `scripts/setup_ssh_passwordless.sh`:

     ```bash
     cd scripts
     ./setup_ssh_passwordless.sh
     ```

5. **Test Ansible Connectivity**:

   ```bash
   ansible -i inventory/hosts.ini k8s_workers -m ping
   ```

   - Expected: `ping: pong`.

6. **Configure AWS CLI**:

   ```bash
   aws configure
   ```

   - Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, region (`us-east-1`), and output format (`json`).

7. **Install Dependencies**:

   ```bash
   sudo pip3 install boto3
   ansible-galaxy collection install amazon.aws
   ```

8. **Update Playbook Variables**:

   - For `configure_irsa.yml` and `configure_eks_autoscaling.yml`:
     - Replace `ansible_aws_account_id` with your AWS account ID.
     - Update `cluster_name`, `subnets`, and `node-role` as needed.

## Usage

Run playbooks with:

```bash
ansible-playbook -i inventory/hosts.ini playbook/<playbook_name>.yml
```

For dynamic inventory:

```bash
ansible-playbook -i inventory/aws_ec2.yml playbook/<playbook_name>.yml
```

**Examples**:

- Deploy Nginx: `ansible-playbook -i inventory/hosts.ini playbook/deploy_helm_app.yml`
- Harden node: `ansible-playbook -i inventory/hosts.ini playbook/harden_eks_node.yml`

**Verification**:

- **site.yml**: `ssh ec2-user@172.31.36.219 "tree --version"`
- **configure_k8s_worker.yml**: `kubectl get nodes k8-worker-partha --show-labels`
- **install_kube_tools.yml**: `ssh ec2-user@172.31.36.219 "kubectl version --client; helm version"`
- **monitor_node.yml**: `cat node_health_k8s-worker-partha.log`
- **deploy_helm_app.yml**: `kubectl get pods -n default -l app.kubernetes.io/name=nginx`
- **configure_log_rotation.yml**: Check CloudWatch Log Group `/eks/k8-worker-partha`
- **configure_irsa.yml**: `kubectl exec -n default s3-test-pod -- aws s3 ls`
- **harden_eks_node.yml**: `ssh ec2-user@172.31.36.219 "getenforce; firewall-cmd --list-services"`
- **configure_eks_autoscaling.yml**: `aws eks list-nodegroups --cluster-name my-eks-cluster`

## Jenkins Integration

Integrate playbooks into Jenkins pipelines for CI/CD automation (March 14, 2025):

1. Install the Ansible plugin in Jenkins.
2. Create a pipeline:

   ```groovy
   pipeline {
       agent any
       stages {
           stage('Deploy Helm App') {
               steps {
                   ansiblePlaybook(
                       playbook: 'partha-ansible/playbook/deploy_helm_app.yml',
                       inventory: 'partha-ansible/inventory/hosts.ini',
                       extras: '-vvv'
                   )
               }
           }
       }
   }
   ```
3. Store `id_rsa_partha` in Jenkins credentials for SSH access.

## Troubleshooting

- **SSH Errors**:
  - Verify `authorized_keys`:

    ```bash
    ssh -i my-key-pair.pem ec2-user@52.55.234.206 "cat ~/.ssh/authorized_keys"
    ```
  - Check permissions: `ls -ld /home/ec2-user/.ssh`
  - Review logs: `sudo tail -f /var/log/secure`
- **Ansible Errors**:
  - Run with verbose: `ansible-playbook -i inventory/hosts.ini playbook/<playbook_name>.yml -vvv`
  - Check logs: `cat ~/ansible/ansible.log`
- **AWS CLI Errors**:
  - Verify credentials: `aws sts get-caller-identity`
  - Check IAM permissions for EKS, S3, CloudWatch.
- **Helm Deployment Fails**:
  - Check repos: `helm repo list`
  - Verify pods: `kubectl describe pod -n default -l app.kubernetes.io/name=nginx`
- **CloudWatch Logs Missing**:
  - Check agent: `ssh ec2-user@172.31.36.219 "sudo systemctl status awslogs"`
  - Verify log group in AWS Console.
- **IRSA Issues**:
  - Confirm OIDC provider: `aws eks describe-cluster --name my-eks-cluster`
  - Check pod logs: `kubectl logs -n default s3-test-pod`
- **Security Hardening**:
  - Test SSH: `ssh ec2-user@172.31.36.219`
  - Verify firewall: `ssh ec2-user@172.31.36.219 "sudo firewall-cmd --list-all"`

## Contributing

- Add new playbooks to `playbook/` for additional EKS tasks (e.g., backup, network policies).
- Update `inventory/aws_ec2.yml` for new nodes.
- Enhance `README.md` with new features.
- Commit changes:

  ```bash
  cp -r ~/partha-ansible ~/jenkins-terraform-k8s-worker/partha-ansible
  cd ~/jenkins-terraform-k8s-worker
  git add partha-ansible/
  git commit -m "Update Ansible playbooks and README"
  git push origin main
  ```

## License

MIT License. See `LICENSE` file in the repository root for details.