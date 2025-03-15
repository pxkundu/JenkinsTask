pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }
    parameters {
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '866934333672', description: 'Which AWS Account to Deploy?')
        string(name: 'GIT_REPO', defaultValue: 'git@github.com:pxkundu/JenkinsTask.git', description: 'GitHub repository URL to clone')
        string(name: 'BRANCH_NAME', defaultValue: 'Staging', description: 'Branch to clone')
    }
    stages {
        stage('Checkout') {
            steps {
                git url: "${GIT_REPO}", branch: "${BRANCH_NAME}"
            }
        }
        stage('Build and Run with Docker Compose') {
            steps {
                sh "docker-compose down || true"  // Stop any running containers
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:${BUILD_NUMBER} || true"
                sh "docker-compose build --no-cache"  // Build fresh from Dockerfiles
                sh "docker-compose up -d"  // Run with BUILD_NUMBER tag
                timeout(time: 30, unit: 'SECONDS') {
                    sh "curl --retry 5 --retry-delay 5 http://localhost/tasks"  // Validate backend
                    sh "curl --retry 5 --retry-delay 5 http://localhost/"      // Validate frontend
                }
            }
            post {
                failure {
                    script {
                        echo "Build or run failed, rolling back to stable ECR images"
                        sh "docker-compose down || true"
                        sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
                        sh "sed -i 's/${BUILD_NUMBER}/latest/g' docker-compose.yml"
                        sh "docker-compose pull"  // Pull stable latest images
                        sh "docker-compose up -d"
                        timeout(time: 30, unit: 'SECONDS') {
                            sh "curl --retry 5 --retry-delay 5 http://localhost/tasks"
                            sh "curl --retry 5 --retry-delay 5 http://localhost/"
                        }
                        sh "sed -i 's/latest/${BUILD_NUMBER}/g' docker-compose.yml"  // Restore for next run
                    }
                }
            }
        }
        stage('Push Latest to ECR and Cleanup') {
            steps {
                sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:latest"
                retry(3) {
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:latest"
                }
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-backend:latest || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-frontend:latest || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/task-nginx:latest || true"
            }
        }
    }
    post {
        always {
            sh "docker-compose logs > compose.log 2>&1 || true"
            archiveArtifacts artifacts: 'compose.log', allowEmptyArchive: true
            sh 'rm -f compose.log'
        }
        success {
            echo "Deploy succeeded for ${APP_NAME} - ${BRANCH_NAME}"
        }
        failure {
            echo "Deploy failed for ${APP_NAME} - ${BRANCH_NAME}. Rolled back to stable ECR images."
        }
    }
}
