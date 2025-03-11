pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }  // Use a specific agent for isolation
    parameters {
        string(name: 'REPO_URL', defaultValue: 'git@github.com:pxkundu/JenkinsTask.git', description: 'GitHub repository URL')
        string(name: 'BRANCH', defaultValue: 'Development', description: 'Branch to clone')
    }
    stages {
        stage('Setup SSH Key') {
            steps {
                script {
                    // Fetch SSH key from AWS Secrets Manager
                    def sshKey = sh(script: "aws secretsmanager get-secret-value --secret-id jenkins-pipeline-secrets --query SecretString --output text", returnStdout: true).trim()
                    def keyPath = "${env.WORKSPACE}/id_rsa"

                    // Write the SSH key to a temporary file
                    writeFile file: keyPath, text: sshKey
                    sh "chmod 600 ${keyPath}"

                    // Configure SSH environment
                    sh '''
                        mkdir -p ~/.ssh
                        ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
                        chmod 600 ~/.ssh/known_hosts
                    '''

                    // Start ssh-agent and add the key
                    sshagent(credentials: []) {
                        sh """
                            eval `ssh-agent -s`
                            ssh-add ${keyPath}
                        """
                    }
                }
            }
        }
        stage('Clone GitHub Repo') {
            steps {
                git branch: params.BRANCH,
                    credentialsId: '',  // No credentialsId needed since ssh-agent is used
                    url: params.REPO_URL
            }
        }
        stage('Install Docker') {
            steps {
                script {
                    try {
                        sh '''
                            chmod +x install_docker.sh
                            ./install_docker.sh
                        '''
                        echo 'Docker installed successfully'
                    } catch (Exception e) {
                        echo "Docker install failed: ${e.getMessage()}"
                        error "Aborting due to Docker install failure"
                    }
                }
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        sh '''
                            sudo docker build -t my-app-image .
                        '''
                        echo 'Docker image built successfully'
                    } catch (Exception e) {
                        echo "Build failed: ${e.getMessage()}"
                        error "Aborting due to build failure"
                    }
                }
            }
        }
        stage('Deploy Container') {
            steps {
                script {
                    try {
                        sh '''
                            chmod +x run_container.sh
                            sudo ./run_container.sh
                        '''
                        echo 'Container deployed successfully'
                    } catch (Exception e) {
                        echo "Deploy failed: ${e.getMessage()}"
                        error "Aborting due to deploy failure"
                    }
                }
            }
        }
    }
    post {
        always {
            // Clean up SSH key and agent
            script {
                def keyPath = "${env.WORKSPACE}/id_rsa"
                sh "rm -f ${keyPath} || true"
                sh "ssh-agent -k || true"  // Kill ssh-agent
            }
        }
        failure {
            echo 'Pipeline failed!'
        }
        success {
            echo 'Pipeline completed successfully! Access your app at http://<slave-public-ip>:8080'
        }
    }
}
