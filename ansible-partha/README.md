# Ansible Setup for Kubernetes Worker Node Management

This directory (`partha-ansible/`) contains Ansible configuration files to manage the Kubernetes worker node `k8-worker-partha` in a Kubernetes cluster hosted on AWS EC2 instances. The setup uses Ansible to configure the worker node (`t2.micro`, private IP `172.31.36.219`) from the control plane node (`jenkins-k8-master`, `t2.medium`), leveraging passwordless SSH with a custom key (`id_rsa_partha`).

## Purpose
The Ansible setup automates configuration tasks for the Kubernetes worker node, such as:
- Installing utility packages (`tree`, `jq`).
- Deploying scripts (e.g., `check_node.sh` for node status).
- Labeling the node for workload organization (e.g., `app=worker`).

This enables efficient management of the worker node without manual SSH intervention, supporting DevOps workflows in the Kubernetes cluster.

## Prerequisites
- **EC2 Instances**:
  - `jenkins-k8-master` (t2.medium, Amazon Linux 2023) as the Kubernetes control plane with `kubectl` configured.
  - `k8-worker-partha` (t2.micro, Amazon Linux 2023, private IP `172.31.36.219`) as the worker node.
- **Ansible**: Installed on `jenkins-k8-master` (`sudo yum install -y epel-release ansible`).
- **SSH Key Pair**:
  - Private key: `/home/ec2-user/.ssh/id_rsa_partha` on `jenkins-k8-master`.
  - Public key: Added to `/home/ec2-user/.ssh/authorized_keys` on `k8-worker-partha`.
- **SSH Configuration**:
  - File: `/home/ec2-user/.ssh/config` on `jenkins-k8-master` with:
    ```
    Host 172.31.36.219
        HostName 172.31.36.219
        User ec2-user
        IdentityFile /home/ec2-user/.ssh/id_rsa_partha
    ```
  - Permissions: `chmod 600 ~/.ssh/config`.
- **Security Group**: `k8s-worker-sg` allows SSH (port 22) from `jenkins-k8-master`’s private IP (e.g., `172.31.1.76/32`).
- **Kubernetes Cluster**: `k8-worker-partha` is joined to the cluster (`kubectl get nodes` shows `Ready`).
- **Git Repository**: Clone `jenkins-terraform-k8s-worker` to `~/jenkins-terraform-k8s-worker` for version control.

## Directory Structure
```
partha-ansible/
├── inventory/
│   ├── hosts.ini
│   └── aws_ec2.yml  # New: Dynamic inventory for AWS EC2
├── playbook/
│   ├── site.yml
│   ├── configure_k8s_worker.yml
│   ├── install_kube_tools.yml  # New: Install Kubernetes tools
│   └── monitor_node.yml       # New: Monitor node health
├── ansible.cfg                # New: Ansible configuration
└── README.md                 # Updated from previous
```

- **hosts.ini**: Defines the `k8s_workers` group with `k8-worker-partha`, specifying the private IP, user, and SSH key.
- **site.yml**: A basic playbook that pings the node, installs `tree`, and verifies its version.
- **configure_k8s_worker.yml**: Configures the node by installing `jq`, deploying a node status script, and labeling the node (`app=worker`).

## Setup Instructions
1. **Clone Repository**:
   ```bash
   cd ~
   git clone <repository-url> jenkins-terraform-k8s-worker
   ```

2. **Copy Ansible Files**:
   ```bash
   mkdir -p ~/partha-ansible
   cp ~/jenkins-terraform-k8s-worker/partha-ansible/* ~/partha-ansible/
   cd ~/partha-ansible
   chmod 644 hosts.ini site.yml configure_k8s_worker.yml
   ```

3. **Verify SSH**:
   ```bash
   ssh ec2-user@172.31.36.219
   ```
   - If it fails, ensure `id_rsa_partha.pub` is in `/home/ec2-user/.ssh/authorized_keys` on `k8-worker-partha`.

4. **Test Ansible Connectivity**:
   ```bash
   ansible -i hosts.ini k8s_workers -m ping
   ```
   - Expected: `ping: pong`.

## Usage
- **Run Basic Playbook**:
  ```bash
  ansible-playbook -i hosts.ini site.yml
  ```
  - Installs `tree` and displays its version.

- **Run Configuration Playbook**:
  ```bash
  ansible-playbook -i hosts.ini configure_k8s_worker.yml
  ```
  - Installs `jq`, deploys `/usr/local/bin/check_node.sh`, and labels the node `app=worker`.

- **Verify Results**:
  - Check `jq`:
    ```bash
    ssh ec2-user@172.31.36.219 "jq --version"
    ```
  - Check script (on `jenkins-k8-master`):
    ```bash
    scp ec2-user@172.31.36.219:/usr/local/bin/check_node.sh .
    chmod +x check_node.sh
    ./check_node.sh
    ```
  - Check label:
    ```bash
    kubectl get nodes k8-worker-partha --show-labels
    ```

## Troubleshooting
- **SSH Errors**:
  - Verify `authorized_keys`:
    ```bash
    ssh -i my-key-pair.pem ec2-user@52.55.234.206
    cat ~/.ssh/authorized_keys
    ```
  - Check permissions:
    ```bash
    ls -ld /home/ec2-user/.ssh
    ls -l /home/ec2-user/.ssh/authorized_keys
    ```
  - Review logs:
    ```bash
    ssh -i my-key-pair.pem ec2-user@52.55.234.206
    sudo tail -f /var/log/secure
    ```

- **Ansible Errors**:
  - Run with verbose:
    ```bash
    ansible-playbook -i hosts.ini configure_k8s_worker.yml -vvv
    ```
  - Check logs:
    ```bash
    cat ~/ansible/ansible.log
    ```

- **kubectl Errors**:
  - Verify:
    ```bash
    kubectl get nodes
    cat ~/.kube/config
    ```

- **Security Group**:
  - Ensure `k8s-worker-sg` allows SSH (port 22) from `172.31.1.76/32`.

## Contributing
- Add new playbooks or tasks to `partha-ansible/`.
- Update this README with new features.
- Commit changes:
  ```bash
  cp -r ~/partha-ansible ~/jenkins-terraform-k8s-worker/partha-ansible
  cd ~/jenkins-terraform-k8s-worker
  git add partha-ansible/
  git commit -m "Update Ansible setup"
  git push origin main
  ```

## License
MIT License. See [LICENSE](LICENSE) for details.
