// Define a method to allow the wrapper pipeline to execute this pipeline
def runPipeline() {
    pipeline {
        agent { label 'Partha-Jenkins-Slave-Agent' }
        stages {
            stage('Verify Workspace') {
                steps {
                    script {
                        // Verify the workspace contains the cloned code
                        sh '''
                            echo "Workspace contents before proceeding:"
                            ls -la
                            echo "Current branch:"
                            git rev-parse --abbrev-ref HEAD
                        '''
                    }
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
            failure {
                echo 'Main pipeline failed!'
            }
            success {
                echo 'Main pipeline completed successfully! Access your app at http://<slave-public-ip>:8080'
            }
        }
    }
}

// Required for Jenkins to load this file
return this
