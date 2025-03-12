pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }  // Run on the slave node
    stages {
        stage('DebugEnvironment') {
            steps {
                script {
                    try {
                        sh '''
                            echo "Git version: $(git --version)"
                            echo "SSH test to GitHub: $(ssh -T git@github.com || echo 'Failed')"
                            echo "Docker version: $(docker --version)"
                        '''
                    } catch (Exception e) {
                        echo "Environment check failed: ${e.getMessage()}"
                        error "Aborting due to environment setup failure"
                    }
                }
            }
        }
        stage('InstallDocker') {
            steps {
                script {
                    try {
                        sh '''
                            # Make the install script executable
                            chmod +x install_docker.sh

                            # Run the Docker installation script
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
        stage('BuildDockerImage') {
            steps {
                script {
                    try {
                        sh '''
                            # Build the Docker image using the Dockerfile from the repo
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
        stage('DeployContainer') {
            steps {
                script {
                    try {
                        sh '''
                            # Make the run script executable
                            chmod +x run_container.sh

                            # Run the container using the script from the repo
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
}
