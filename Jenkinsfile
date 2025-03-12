// Define a method to allow the wrapper pipeline to execute this pipeline
def runPipeline() {
    stage('Verify Workspace') {
        steps {
            script {
                // Verify the workspace contains the cloned code
                sh '''
                    echo "Workspace contents before proceeding:"
                    ls -la
                    echo "Current branch:"
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

// Required for Jenkins to load this file
return this
