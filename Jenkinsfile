pipeline {
    agent none
    parameters {
        string(name: 'BRANCH_NAME', defaultValue: 'main', description: 'Git branch')
    }
    environment {
        APP_NAME = 'task-manager'
        GIT_REPO = 'https://github.com/<your-username>/task-manager.git'
        S3_BUCKET = 'jenkinsartifactstoreforcicd'
        DEPLOY_INSTANCE = 'TaskManagerProd'
        AWS_REGION = 'us-east-1'
    }
    stages {
        stage('Setup S3 Bucket') {
            agent { label 'docker-slave-east' }
            steps {
                withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                    sh """
                        aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION} || echo "Bucket already exists"
                        aws s3api put-bucket-encryption --bucket ${S3_BUCKET} --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]}'
                        aws s3api put-public-access-block --bucket ${S3_BUCKET} --public-access-block-configuration '{"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": true, "RestrictPublicBuckets": true}'
                        aws s3api put-bucket-policy --bucket ${S3_BUCKET} --policy '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::<account-id>:role/JenkinsSlaveRole"}, "Action": ["s3:PutObject", "s3:GetObject"], "Resource": "arn:aws:s3:::${S3_BUCKET}/*"}]}'
                    """
                }
            }
        }
        stage('Checkout and Build') {
            parallel {
                stage('Backend') {
                    agent { label 'docker-slave-east' }
                    steps {
                        withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                            script {
                                def githubSecret = sh(script: 'aws secretsmanager get-secret-value --secret-id github-token --query SecretString --output text', returnStdout: true).trim()
                                def githubCreds = readJSON text: githubSecret
                                env.GIT_USER = githubCreds.username
                                env.GIT_TOKEN = githubCreds.token
                            }
                            git url: "${GIT_REPO}", branch: "${BRANCH_NAME}", credentialsId: 'github-token'
                            sh "docker build -t task-backend:${BUILD_NUMBER} backend/"
                            sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com"
                            sh "docker tag task-backend:${BUILD_NUMBER} <account-id>.dkr.ecr.us-east-1.amazonaws.com/task-backend:${BUILD_NUMBER}"
                            retry(3) {
                                sh "docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/task-backend:${BUILD_NUMBER}"
                            }
                        }
                    }
                }
                stage('Frontend') {
                    agent { label 'docker-slave-west' }
                    steps {
                        withAWS(credentials: 'aws-creds', region: 'us-west-2') {
                            git url: "${GIT_REPO}", branch: "${BRANCH_NAME}", credentialsId: 'github-token'
                            sh "docker build -t task-frontend:${BUILD_NUMBER} frontend/"
                            sh "aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com"
                            sh "docker tag task-frontend:${BUILD_NUMBER} <account-id>.dkr.ecr.us-west-2.amazonaws.com/task-frontend:${BUILD_NUMBER}"
                            retry(3) {
                                sh "docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/task-frontend:${BUILD_NUMBER}"
                            }
                        }
                    }
                }
                stage('Nginx') {
                    agent { label 'docker-slave-east' }
                    steps {
                        withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                            git url: "${GIT_REPO}", branch: "${BRANCH_NAME}", credentialsId: 'github-token'
                            sh "docker build -t task-nginx:${BUILD_NUMBER} nginx/"
                            sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com"
                            sh "docker tag task-nginx:${BUILD_NUMBER} <account-id>.dkr.ecr.us-east-1.amazonaws.com/task-nginx:${BUILD_NUMBER}"
                            retry(3) {
                                sh "docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/task-nginx:${BUILD_NUMBER}"
                            }
                        }
                    }
                }
            }
        }
        stage('Deploy') {
            agent { label 'docker-slave-east' }
            steps {
                withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                    script {
                        def sshKey = sh(script: 'aws secretsmanager get-secret-value --secret-id jenkins-ssh-key --query SecretString --output text', returnStdout: true).trim()
                        writeFile file: 'id_rsa', text: sshKey
                        sh 'chmod 600 id_rsa'
                        def instanceIp = sh(script: "aws ec2 describe-instances --filters Name=tag:Name,Values=${DEPLOY_INSTANCE} Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text", returnStdout: true).trim()
                        sh "sed -i 's/<BUILD_NUMBER>/${BUILD_NUMBER}/g' docker-compose.yml"
                        sh """
                            ssh -i id_rsa -o StrictHostKeyChecking=no ec2-user@${instanceIp} '
                                docker-compose down || true
                                aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
                                aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com
                            '
                            scp -i id_rsa docker-compose.yml ec2-user@${instanceIp}:/home/ec2-user/docker-compose.yml
                            ssh -i id_rsa ec2-user@${instanceIp} '
                                docker-compose up -d
                            '
                            aws s3 cp docker-compose.yml s3://${S3_BUCKET}/configs/docker-compose-${BUILD_NUMBER}.yml --sse aws:kms
                        """
                        timeout(time: 30, unit: 'SECONDS') {
                            sh "curl --retry 5 --retry-delay 5 http://${instanceIp}/tasks"
                        }
                    }
                }
            }
            post {
                failure {
                    withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                        script {
                            def instanceIp = sh(script: "aws ec2 describe-instances --filters Name=tag:Name,Values=${DEPLOY_INSTANCE} Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text", returnStdout: true).trim()
                            sh "sed -i 's/${BUILD_NUMBER}/${BUILD_NUMBER.toInteger() - 1}/g' docker-compose.yml"
                            sh """
                                ssh -i id_rsa ec2-user@${instanceIp} '
                                    docker-compose down || true
                                '
                                scp -i id_rsa docker-compose.yml ec2-user@${instanceIp}:/home/ec2-user/docker-compose.yml
                                ssh -i id_rsa ec2-user@${instanceIp} '
                                    docker-compose up -d
                                '
                                aws s3 cp docker-compose.yml s3://${S3_BUCKET}/configs/docker-compose-${BUILD_NUMBER}-rollback.yml --sse aws:kms
                            """
                        }
                    }
                }
            }
        }
    }
    post {
        always {
            withAWS(credentials: 'aws-creds', region: 'us-east-1') {
                sh 'docker logs task-backend > backend.log 2>&1 || true'
                sh 'docker logs task-frontend > frontend.log 2>&1 || true'
                sh 'docker logs task-nginx > nginx.log 2>&1 || true'
                sh "aws s3 cp backend.log s3://${S3_BUCKET}/logs/backend-${BUILD_NUMBER}.log --sse aws:kms || true"
                sh "aws s3 cp frontend.log s3://${S3_BUCKET}/logs/frontend-${BUILD_NUMBER}.log --sse aws:kms || true"
                sh "aws s3 cp nginx.log s3://${S3_BUCKET}/logs/nginx-${BUILD_NUMBER}.log --sse aws:kms || true"
            }
            sh 'rm -f id_rsa *.log'
        }
        success {
            echo "Deploy succeeded for ${APP_NAME} - ${BRANCH_NAME}"
        }
        failure {
            echo "Deploy failed for ${APP_NAME} - ${BRANCH_NAME}. Rolled back."
        }
    }
}
