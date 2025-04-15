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
                    // Get k8-worker public IP from Terraform output
                    def workerIp = sh(script: 'terraform output -raw k8_worker_public_ip', returnStdout: true).trim()
                    
                    // Write SSH key to a temporary file
                    writeFile file: 'k8-worker-key-partha-1', text: env.K8_WORKER_SSH_KEY
                    
                    // Set permissions for SSH key
                    sh 'chmod 400 k8-worker-key-partha-1'
                    
                    // SSH into k8-worker and run kubeadm join
                    sh """
                        ssh -i k8-worker-key-partha -o StrictHostKeyChecking=no ec2-user@${workerIp} << 'EOF'
                        sudo ${KUBEADM_JOIN_CMD}
                        EOF
                    """
                    
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
                sh 'terraform destroy -auto-approve'
        }
    }
}
