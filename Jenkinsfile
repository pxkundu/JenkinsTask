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

        stage('Generate SSH Key Pair') {
            steps {
                script {
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
                    // Use the dynamically generated public key
                    sh 'terraform apply -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}"'
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
                    def masterIp = "3.83.26.46"
                    
                    // Construct kubeadm join command
                    env.KUBEADM_JOIN_CMD = "kubeadm join ${masterIp}:6443 --token ${token} --discovery-token-ca-cert-hash sha256:${caHash}"
                    
                    // Debug: Print the constructed join command
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

                    // Test SSH connectivity using the generated private key
                    sh "ssh -i k8-worker-key -o StrictHostKeyChecking=no ec2-user@${workerIp} 'echo SSH connection successful; hostname; whoami'"

                    // Run kubeadm join command
                    sh """
                        ssh -i k8-worker-key -o StrictHostKeyChecking=no ec2-user@${workerIp} << EOF
                        sudo ${KUBEADM_JOIN_CMD}
EOF
                    """

                    // Clean up the generated key files
                    sh 'rm k8-worker-key k8-worker-key.pub'
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
            script {
                sh 'terraform destroy -auto-approve -var="ssh_public_key=${SSH_PUBLIC_KEY}"'
            }
        }
    }
}
