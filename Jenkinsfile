pipeline {
    agent any
    parameters {
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'Which AWS Region to Deploy?')
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '866934333672', description: 'Which AWS Account to Deploy?')
    }
    environment {
        ECR_REPO_BASE = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/partha-ecr"
        BACKEND_IMAGE = "nodejs-cicd-frontend"
        FRONTEND_IMAGE = "nodejs-cicd-backend"
    }
    stages {
        stage('Fetch GitHub SSH Key') {
            steps {
                script {
                    // Fetch the secret from AWS Secrets Manager
                    def secretKey = sh(script: "aws secretsmanager get-secret-value --secret-id partha-jenkins-pipeline-secrets --query SecretString --output text", returnStdout: true).trim()
    
                    // Fetch and parse the secret in one step, avoiding intermediate logging
                    def SSHKey = sh(script: """
                        aws secretsmanager get-secret-value --secret-id partha-jenkins-pipeline-secrets --query SecretString --output text | jq -r '.\"partha-jenkins-pipeline-secrets\"'
                    """, returnStdout: true).trim()
    
                    // Clean up key (replace \\n with actual newline, remove extra spaces, etc.)
                    def cleanedKey = SSHKey.replaceAll('\\\\n', '\n').trim()
    
    
                    // Configure SSH environment
                    sh """
                        echo "$cleanedKey" > ~/.ssh/github
                        chmod 600 ~/.ssh/github
                        
                        echo -e "Host github.com\n  HostName github.com\n   IdentityFile ~/.ssh/github\n  StrictHostKeyChecking no\n  User git" > ~/.ssh/config
                        chmod 600 ~/.ssh/config
                        chown jenkinss:jenkinss ~/.ssh/config
                    """
                }
            }
        }
        stage('Checkout') {
            steps {
                git branch: 'Development',
                    credentialsId: '',
                    url: 'git@github.com:pxkundu/JenkinsTask.git'
            }
        }
        stage('Build and Deploy') {
            steps {
                sh 'docker-compose up -d --build'
                sh 'docker ps -a'
            }
        }
        stage('Push to ECR') {
            steps {
                script {
                    // Tag images for ECR
                    sh 'docker tag ${BACKEND_IMAGE} ${ECR_REPO_BASE}:${BACKEND_IMAGE}'
                    sh 'docker tag ${FRONTEND_IMAGE} ${ECR_REPO_BASE}:${FRONTEND_IMAGE}'
                    // Push images to ECR
                    sh 'docker push ${ECR_REPO_BASE}:${BACKEND_IMAGE}'
                    sh 'docker push ${ECR_REPO_BASE}:${FRONTEND_IMAGE}'
                }
            }
        }
    }
    post {
        always {
            echo 'Pipeline completed!'
        }
    }
}
