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
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-${BUILD_NUMBER} || true"
                sh "docker-compose build --no-cache"  // Build fresh from Dockerfiles
                sh "docker-compose up -d"  // Run with BUILD_NUMBER tag
                sh "docker ps -a"
                sh "docker-compose logs"
                timeout(time: 30, unit: 'SECONDS') {
                    sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/tasks"  // Validate backend
                    sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/"      // Validate frontend
                }
            }
            post {
                failure {
                    script {
                        echo "Build or run failed, rolling back to stable ECR images"
                        sh "docker-compose down || true"
                        sh "sed -i 's/${BUILD_NUMBER}/latest/g' docker-compose.yml"
                        sh "docker-compose pull"  // Pull stable latest images
                        sh "docker-compose up -d --build"  // Run with stable latest images
                        sh "docker ps -a"
                        sh "docker-compose logs"
                        timeout(time: 30, unit: 'SECONDS') {
                            sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/tasks"
                            sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/"
                        }
                        sh "sed -i 's/latest/${BUILD_NUMBER}/g' docker-compose.yml"  // Restore for next run
                    }
                }
            }
        }
        stage('Push Latest to ECR and Cleanup') {
            steps {
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-latest"
                retry(3) {
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-latest"
                }
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-${BUILD_NUMBER} || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-latest || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-latest || true"
                sh "docker image rm ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-latest || true"
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
            echo "Deploy succeeded for Task manager project - ${BRANCH_NAME}"
        }
        failure {
            echo "Deploy failed for Task manager project  - ${BRANCH_NAME}. Rolled back to stable ECR images."
        }
    }
}
