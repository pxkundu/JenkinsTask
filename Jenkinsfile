pipeline {
    agent any
    environment {
        DOCKER_CRED = credentials('dockerhub-pxkundu')
        GITHUB_CRED = credentials('github-pxkundu')
        REPO_URL = 'https://github.com/pxkundu/JenkinsTask.git'
        BRANCH = 'main'
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: "${BRANCH}", url: "${REPO_URL}", credentialsId: 'github-pxkundu'
            }
        }
        stage('Build and Push Frontend') {
            steps {
                sh '''
                cd frontend
                docker build -t pxkundu/todo-frontend:${BUILD_NUMBER} .
                docker login -u ${DOCKER_CRED_USR} -p ${DOCKER_CRED_PSW}
                docker push pxkundu/todo-frontend:${BUILD_NUMBER}
                '''
            }
        }
        stage('Build and Push Backend') {
            steps {
                sh '''
                cd backend
                docker build -t pxkundu/todo-backend:${BUILD_NUMBER} .
                docker login -u ${DOCKER_CRED_USR} -p ${DOCKER_CRED_PSW}
                docker push pxkundu/todo-backend:${BUILD_NUMBER}
                '''
            }
        }
        stage('Update Helm Chart') {
            steps {
                sh '''
                sed -i "s/frontend:.*tag: \\"latest\\"/frontend: tag: \\"${BUILD_NUMBER}\\"/g" helm-charts/todo-app/values.yaml
                sed -i "s/backend:.*tag: \\"latest\\"/backend: tag: \\"${BUILD_NUMBER}\\"/g" helm-charts/todo-app/values.yaml
                git config user.email "jenkins@example.com"
                git config user.name "Jenkins CI"
                git add helm-charts/todo-app/values.yaml
                git commit -m "Update image tags to ${BUILD_NUMBER} [skip ci]" || echo "No changes to commit"
                git push origin ${BRANCH}
                '''
            }
        }
    }
    post {
        success {
            echo 'CI completed. ArgoCD will deploy the app.'
        }
        failure {
            echo 'CI failed. Check logs.'
        }
    }
}
