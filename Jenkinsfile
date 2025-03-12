pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }
    stages {
        stage('Debug Environment') {
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
        stage('Fetch API Key and Configure') {
            steps {
                script {
                    // Fetch the secret from AWS Secrets Manager
                    def secretJson = sh(script: "aws secretsmanager get-secret-value --secret-id jenkins-pipeline-secrets --query SecretString --output text", returnStdout: true).trim()
                    echo "Raw secret JSON: ${secretJson}"  // Debug: Log the raw secret

                    // Parse JSON to extract the api_key
                    def apiConfig
                    try {
                        apiConfig = readJSON(text: secretJson)
                    } catch (NoSuchMethodError e) {
                        echo "readJSON not found, falling back to JsonSlurper"
                        apiConfig = new groovy.json.JsonSlurper().parseText(secretJson)
                    }

                    def apiKey = apiConfig.api_key
                    echo "API Key fetched (first 8 chars): ${apiKey.substring(0, Math.min(8, apiKey.length()))}..."  // Debug: Partial log

                    // Write the API key to config.json
                    writeFile file: 'config/config.json', text: "{\"api_key\": \"${apiKey}\"}"
                }
            }
          }
          stage('Build Docker Image') {
              steps {
                  script {
                      try {
                          sh '''
                              # Build the Docker image with the updated config
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
      post {
          failure {
              echo 'Pipeline failed!'
          }
          success {
              echo 'Pipeline completed successfully! Access weather data at http://<slave-public-ip>:8080/weather'
          }
      }
  }
