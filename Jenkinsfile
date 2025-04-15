pipeline {
    agent any

    environment {
//        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')      // Jenkins credential ID for AWS access key
//        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')  // Jenkins credential ID for AWS secret key
        K8_WORKER_SSH_KEY     = credentials('k8-worker-ssh-key')     // Jenkins credential ID for SSH private key
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
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
                    // Verify the public key file exists
                    if (!fileExists('/var/lib/jenkins/k8-worker-key-partha-1.pub')) {
                        error "Public key file /var/lib/jenkins/k8-worker-key-partha-1.pub not found on jenkins-k8-master. Please ensure the file exists and is readable by the jenkins user."
                    }
                    sh 'terraform apply -auto-approve -var="ssh_public_key=$(cat /var/lib/jenkins/k8-worker-key-partha-1.pub)"'
                }
            }
        }

        stage('Get Kubeadm Join Command') {
            steps {
                script {
                    // Extract kubeadm token using sudo
                    def token = sh(script: 'sudo kubeadm token create', returnStdout: true).trim()
                    
                    // Get CA certificate hash using sudo
                    def caHash = sh(script: 'sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //"', returnStdout: true).trim()
                    
                    // Get k8-master API server endpoint (public IP)
                    def masterIp = sh(script: 'curl -s http://169.254.169.254/latest/meta-data/public-ipv4', returnStdout: true).trim()
                    
                    // Construct kubeadm join command
                    env.KUBEADM_JOIN_CMD = "kubeadm join ${masterIp}:6443 --token ${token} --discovery-token-ca-cert-hash sha256:${caHash}"
                }
            }
        }

      
        stage('Join Worker to Cluster') {
            steps {
                script {
                    // Get k8-worker public IP from Terraform output with timeout and debug
                    def terraformOutput
                    try {
                        timeout(time: 30, unit: 'SECONDS') {
                            terraformOutput = sh(script: 'terraform output -raw k8_worker_public_ip 2>&1', returnStdout: true).trim()
                        }
                    } catch (Exception e) {
                        error "Failed to retrieve k8-worker public IP: ${e.message}\nTerraform output: ${terraformOutput}"
                    }
                    echo "Terraform output (k8_worker_public_ip): ${terraformOutput}"
                    
                    def workerIp = terraformOutput
                    echo "Worker IP: ${workerIp}"
                    
                    // Debug: Checkpoint to confirm pipeline proceeds
                    echo "Checkpoint: Proceeding to write SSH key file..."
                    
                    // Write SSH key to a temporary file
                    writeFile file: 'k8-worker-key-partha-1', text: env.K8_WORKER_SSH_KEY
                    
                    // Debug: Inspect the key file
                    sh 'ls -l k8-worker-key-partha-1'
                    sh 'head -n 2 k8-worker-key-partha-1'
                    
                    // Set permissions for SSH key
                    sh 'chmod 400 k8-worker-key-partha-1'
                    
                    // Debug: Test SSH connectivity
                    sh "ssh -i k8-worker-key-partha-1 -o StrictHostKeyChecking=no ec2-user@${workerIp} 'echo SSH connection successful; hostname; whoami'"
                    
                    // SSH into k8-worker and run kubeadm join with debug output
                    def joinOutput = sh(script: """
                        ssh -i k8-worker-key-partha-1 -o StrictHostKeyChecking=no ec2-user@${workerIp} << 'EOF'
                        echo "Running kubeadm join command..."
                        sudo ${KUBEADM_JOIN_CMD} 2>&1
                        JOIN_EXIT_CODE=\$?
                        echo "kubeadm join exit code: \$JOIN_EXIT_CODE"
                        if [ \$JOIN_EXIT_CODE -ne 0 ]; then
                            echo "kubeadm join failed. Checking node status..."
                            sudo kubeadm reset -f 2>&1
                            exit \$JOIN_EXIT_CODE
                        fi
                        echo "Checking Kubernetes components..."
                        sudo systemctl status kubelet 2>&1
                        sudo journalctl -u kubelet -n 50 2>&1
                        EOF
                    """, returnStdout: true).trim()
                    
                    echo "kubeadm join output:\n${joinOutput}"
                    
                    // Clean up SSH key file
                    sh 'rm k8-worker-key-partha-1'
                }
            }
        }

        stage('Verify Worker Node') {
            steps {
                sh 'kubectl get nodes -o wide'
            }
        }
    }
    post {
        always {
                sh 'terraform output'
        }
        failure {
            sh 'terraform destroy -auto-approve -var="ssh_public_key=$(cat /var/lib/jenkins/k8-worker-key-partha-1.pub)"'        }
    }
}
