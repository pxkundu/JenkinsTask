pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Generate SSH Key Pair') {
            steps {
                script {
                    // Destroy before running again
                    sh 'terraform destroy -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}"'
                    // Remove existing key files if they exist
                    sh 'rm -f k8-worker-key k8-worker-key.pub'
                    // Generate a new SSH key pair in the workspace
                    sh 'ssh-keygen -t rsa -b 2048 -f k8-worker-key -N "" -C "k8-worker-key"'
                    // Set permissions for the private key
                    sh 'chmod 400 k8-worker-key'
                    // Read the public key into a variable for Terraform
                    env.SSH_PUBLIC_KEY = sh(script: 'cat k8-worker-key.pub', returnStdout: true).trim()
                    echo "Generated SSH public key: ${env.SSH_PUBLIC_KEY}"
                }
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Apply') {
            steps {
                script {
                    sh 'terraform apply -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}"'
                }
            }
        }

        stage('Get Kubeadm Join Command') {
            steps {
                script {
                    // Extract kubeadm token using sudo
                    def token = sh(script: 'sudo kubeadm token create', returnStdout: true).trim()
                    if (!token || token =~ /[^a-z0-9.]/) {
                        error "Failed to generate a valid kubeadm token: ${token}"
                    }
                    
                    // Get CA certificate hash using sudo
                    def caHash = sh(script: 'sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //"', returnStdout: true).trim()
                    if (!caHash || caHash =~ /[^a-f0-9]/) {
                        error "Failed to generate a valid CA certificate hash: ${caHash}"
                    }
                    
                    // Get k8-master internal IP using AWS CLI
                    def masterIp = "172.31.1.179"
                    
                    // Construct kubeadm join command using the internal IP
                    env.KUBEADM_JOIN_CMD = "kubeadm join ${masterIp}:6443 --token ${token} --discovery-token-ca-cert-hash sha256:${caHash}"
                    echo "KUBEADM_JOIN_CMD: ${env.KUBEADM_JOIN_CMD}"
                }
            }
        }

        stage('Join Worker to Cluster') {
            steps {
                script {
                    // Get k8-worker public IP from Terraform output
                    def workerIp = sh(script: 'terraform output -raw k8_worker_public_ip', returnStdout: true).trim()
                    echo "Worker IP: ${workerIp}"

                    // Get k8-worker internal IP (needed for /etc/hosts)
                    def workerInternalIp = sh(script: "aws ec2 describe-instances --filters 'Name=public-ip-address,Values=${workerIp}' --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text --region us-east-1", returnStdout: true).trim()
                    if (!workerInternalIp || workerInternalIp =~ /[^0-9.]/) {
                        error "Failed to retrieve a valid worker internal IP: ${workerInternalIp}"
                    }
                    echo "Worker Internal IP: ${workerInternalIp}"

                    // Test SSH connectivity using the generated private key
                    sh "ssh -i k8-worker-key -o StrictHostKeyChecking=no ec2-user@${workerIp} 'echo SSH connection successful; hostname; whoami'"

                    // Set up the worker node and run kubeadm join command
                    sh """
                        ssh -i k8-worker-key -o StrictHostKeyChecking=no ec2-user@${workerIp} << EOF
                        # Update hostname and /etc/hosts
                        echo "Setting hostname to k8-worker-partha..."
                        sudo hostnamectl set-hostname k8-worker-partha
                        sudo bash -c 'echo "${workerInternalIp} k8-worker-partha" >> /etc/hosts'
                        echo "Updated /etc/hosts with: ${workerInternalIp} k8-worker-partha"

                        # Update system and install basic utilities
                        echo "Updating system..."
                        for i in {1..5}; do
                            sudo yum update -y && break
                            echo "Retry \$i: yum update failed, waiting 10 seconds..."
                            sleep 10
                        done

                        # Install iproute to provide tc command
                        echo "Installing iproute for tc command..."
                        for i in {1..5}; do
                            sudo yum install -y iproute && break
                            echo "Retry \$i: yum install iproute failed, waiting 10 seconds..."
                            sleep 10
                        done

                        # Install containerd as container runtime
                        echo "Installing containerd..."
                        for i in {1..5}; do
                            sudo yum install -y containerd && break
                            echo "Retry \$i: yum install containerd failed, waiting 10 seconds..."
                            sleep 10
                        done
                        sudo systemctl enable containerd
                        sudo systemctl start containerd

                        # Configure containerd
                        sudo mkdir -p /etc/containerd
                        containerd config default | sudo tee /etc/containerd/config.toml
                        sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
                        sudo systemctl restart containerd

                        # Disable SELinux (simplified for learning)
                        sudo setenforce 0
                        sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

                        # Disable swap (Kubernetes requirement)
                        sudo swapoff -a
                        sudo sed -i '/swap/d' /etc/fstab

                        # Load required kernel modules
                        echo "Loading kernel modules..."
                        sudo modprobe br_netfilter
                        echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf

                        # Enable IP forwarding and bridge iptables
                        echo "Enabling IP forwarding and bridge iptables..."
                        sudo sysctl -w net.ipv4.ip_forward=1
                        sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
                        sudo bash -c 'cat <<EOT > /etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOT'
                        sudo sysctl --system

                        # Install Kubernetes components
                        echo "Installing Kubernetes components..."
                        sudo bash -c 'cat <<EOT > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOT'

                        for i in {1..5}; do
                            sudo yum install -y kubelet kubeadm && break
                            echo "Retry \$i: yum install kubelet kubeadm failed, waiting 10 seconds..."
                            sleep 10
                        done

                        # Verify kubeadm is installed
                        if ! command -v kubeadm &> /dev/null; then
                            echo "ERROR: kubeadm installation failed"
                            exit 1
                        fi

                        sudo systemctl enable kubelet
                        sudo systemctl start kubelet

                        # Run kubeadm join command
                        sudo ${KUBEADM_JOIN_CMD}
EOF
                    """

                    // Clean up the generated key files
                    sh 'rm -f k8-worker-key k8-worker-key.pub'
                }
            }
        }

        stage('Verify Worker Node') {
            steps {
                sh 'sudo kubectl get nodes -o wide'
            }
        }
    }

    post {
        always {
            sh 'terraform output || true'  // Ignore errors if output fails
        }
        failure {
            script {
                sh 'terraform destroy -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}"'
            }
        }
    }
}
