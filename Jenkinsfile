pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }
    parameters {
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '866934333672', description: 'Which AWS Account to Deploy?')
        string(name: 'GIT_REPO', defaultValue: 'git@github.com:pxkundu/JenkinsTask.git', description: 'GitHub repository URL to clone')
        string(name: 'BRANCH_NAME', defaultValue: 'Staging', description: 'Branch to clone')
    }
    
    stages {
        stage('Setup SSH Key and Clone Repo') {
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
        stage('Clone and Checkout') {
            steps {
                git url: "${GIT_REPO}", branch: "${BRANCH_NAME}"
            }
        }
        stage('Load and Run Main Jenkinsfile') {
            steps {
                script {
                    // Load and execute Jenkinsfile.functions from the cloned repo
                    def pipelineScript = load "Jenkinsfile.functions"
                    pipelineScript.checkDockerFileChanges()
                    pipelineScript.buildAndRunWithDockerCompose()
                    pipelineScript.checkAndPushToECR()
                }
            }
        }
    }
    post {
        always {
            // Cleanup SSH key and config
            sh "rm -f ~/.ssh/github || true"
            sh "rm -f /home/jenkinss/.ssh/config || true"
            sh "docker system prune -f || true"  // Clean unused images
            sh "mkdir -p /home/jenkinss/deployed && cp docker-compose.yml /home/jenkinss/deployed/ || true"
            sh "rm -rf /home/jenkinss/workspace/Partha-jengit-Pipeline/* || true"
            sh "cd /home/jenkinss/deployed && docker-compose logs > compose.log 2>&1 || true"
            archiveArtifacts artifacts: '/home/jenkinss/deployed/compose.log', allowEmptyArchive: true
        }
        success {
            echo "Deploy succeeded for Task manager project - ${BRANCH_NAME}"
        }
        failure {
            echo "Deploy failed for Task manager project - ${BRANCH_NAME}. Rolled back to stable ECR images."
        }
    }
}