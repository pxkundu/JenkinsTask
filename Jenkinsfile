pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }
    parameters {
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '866934333672', description: 'Which AWS Account to Deploy?')
        string(name: 'GIT_REPO', defaultValue: 'git@github.com:pxkundu/JenkinsTask.git', description: 'GitHub repository URL to clone')
        string(name: 'BRANCH_NAME', defaultValue: 'Staging', description: 'Branch to clone')
    }
    environment {
        DOCKERFILE_CHANGES = 'false'
    }
    stages {
        stage('Checkout') {
            steps {
                git url: "${GIT_REPO}", branch: "${BRANCH_NAME}"
            }
        }
        stage('Check Dockerfile Changes') {
            steps {
                script {
                    def changes = sh(script: "git diff --name-only HEAD^ HEAD | grep -E 'backend/Dockerfile|frontend/Dockerfile|nginx/Dockerfile' || true", returnStdout: true).trim()
                    if (changes) {
                        echo "Dockerfile changes detected: ${changes}"
                        env.DOCKERFILE_CHANGES = 'true'
                    } else {
                        echo "No Dockerfile changes detected"
                    }
                }
            }
        }
        stage('Build and Run with Docker Compose') {
            steps {
                sh "docker-compose down -v || true"  // Clean start for this build
                sh "docker-compose build --no-cache"  // Build fresh
                sh "docker-compose up -d"  // Deploy and keep running
                sh "docker ps -a"
                timeout(time: 30, unit: 'SECONDS') {
                    sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/api/tasks"
                    sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/"
                }
            }
            post {
                failure {
                    script {
                        echo "Build or run failed, rolling back to stable ECR images"
                        sh "docker-compose down -v || true"
                        sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
                        sh "sed -i 's/task-backend-${BUILD_NUMBER}/task-backend-latest/g' docker-compose.yml"
                        sh "sed -i 's/task-frontend-${BUILD_NUMBER}/task-frontend-latest/g' docker-compose.yml"
                        sh "sed -i 's/task-nginx-${BUILD_NUMBER}/task-nginx-latest/g' docker-compose.yml"
                        sh "docker-compose pull || echo 'No stable images found in ECR, skipping pull'"
                        sh "docker-compose up -d"  // Redeploy stable images
                        timeout(time: 30, unit: 'SECONDS') {
                            sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/api/tasks"
                            sh "curl --retry 5 --retry-delay 5 http://partha.snehith-dev.com/"
                        }
                        sh "sed -i 's/task-backend-latest/task-backend-${BUILD_NUMBER}/g' docker-compose.yml"
                        sh "sed -i 's/task-frontend-latest/task-frontend-${BUILD_NUMBER}/g' docker-compose.yml"
                        sh "sed -i 's/task-nginx-latest/task-nginx-${BUILD_NUMBER}/g' docker-compose.yml"
                    }
                }
            }
        }
        stage('Push Latest to ECR') {
            when {
                expression { env.DOCKERFILE_CHANGES == 'true' }
            }
            steps {
                sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-latest"
                sh "docker tag ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-latest"
                retry(3) {
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-backend-latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-frontend-latest"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/partha-ecr:task-nginx-latest"
                }
            }
        }
    }
    post {
        always {
            // Selective cleanup: keep running containers
            sh "docker system prune -f --volumes || true"  // Remove unused images/volumes, keep running containers
            // Move docker-compose.yml and source to a persistent dir if needed
            sh "mkdir -p /home/jenkinss/deployed && cp docker-compose.yml /home/jenkinss/deployed/ || true"
            sh "rm -rf /home/jenkinss/workspace/Partha-jengit-Pipeline/* || true"  // Clear workspace
            sh "cd /home/jenkinss/deployed && docker-compose logs > compose.log 2>&1 || true"
            archiveArtifacts artifacts: '/home/jenkinss/deployed/compose.log', allowEmptyArchive: true
            sh "rm -f /home/jenkinss/deployed/compose.log || true"
        }
        success {
            echo "Deploy succeeded for Task manager project - ${BRANCH_NAME}"
        }
        failure {
            echo "Deploy failed for Task manager project - ${BRANCH_NAME}. Rolled back to stable ECR images."
        }
    }
}