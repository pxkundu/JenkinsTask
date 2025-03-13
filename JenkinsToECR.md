This is a **comprehensive step-by-step guide** to complete the task, starting from the point where we already have the **root domain** and **Jenkins Master/Slave EC2 instances deployed**. This guide will help to:

1. **Set up Jenkins to deploy a Docker image to Amazon ECR**.
2. **Set up Route 53** to manage your domain and DNS records.
3. **Configure Reverse Proxy (Nginx)** to handle requests on ports 5000 and 8080.
4. **Set up IAM role** for EC2 instances.
5. **Run the Jenkins pipeline to deploy Docker images**.

---

## **Step 1: Prerequisites**

Before starting, ensure the following are in place:

1. **Root Domain** is managed by **Route 53** (i.e., `snehith-dev.com`).
2. **Jenkins Master** is deployed and accessible at `http://central-jenkins.snehith-dev.com:8080/`.
3. **Jenkins Slave Node** is deployed and connected to the Jenkins Master.
4. **Amazon ECR** repository `partha-ecr` has been created and is ready for Docker image storage.
5. **IAM role** with sufficient permissions (such as `AmazonECRFullAccess` and `AmazonEC2ContainerRegistryReadOnly`) has been assigned to the EC2 instances.

---

## **Step 2: Configure Jenkins Master and Slave Nodes**

### **2.1 Verify Jenkins Master Setup**

1. **Access Jenkins Master**:
   - Open the Jenkins Master URL: `http://central-jenkins.snehith-dev.com:8080/`.

2. **Install Required Plugins**:
   - Navigate to **Manage Jenkins** → **Manage Plugins**.
   - Install the following plugins:
     - **Docker Pipeline** (for Docker-related steps in the pipeline).
     - **AWS CLI Plugin** (to interact with AWS services).
     - **SSH Agent Plugin** (to allow Jenkins to connect to GitHub using SSH).
     - **Git Plugin** (for GitHub integration).

3. **Configure Global Tools**:
   - Go to **Manage Jenkins** → **Global Tool Configuration**.
   - Set up **JDK** (Java 17, since Jenkins requires it):
     - Name: `JDK 17`
     - Install Automatically: Select the version or provide the path.
   - Set up **Docker**:
     - Name: `Docker`
     - Path to Docker executable: `/usr/bin/docker` (if installed on Jenkins Master).

---

### **2.2 Configure Jenkins Slave Node**

1. **SSH Key for Slave Node**:
   - SSH into the **Jenkins Slave EC2 instance**:

     ```bash
     ssh -i your-key.pem ec2-user@partha.snehith-dev.com
     ```

2. **Install Docker on Jenkins Slave**:

   ```bash
   sudo yum install docker -y
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

3. **Configure SSH for Jenkins Master**:
   - On the Jenkins Slave instance, generate an SSH key pair:

     ```bash
     ssh-keygen -t rsa -b 4096 -C "jenkins-slave" -f ~/.ssh/jenkins_slave_key
     ```

   - Copy the public key to the **Jenkins Master**:

     ```bash
     ssh-copy-id -i ~/.ssh/jenkins_slave_key.pub ec2-user@central-jenkins.snehith-dev.com
     ```

4. **Add the Jenkins Slave Node in the Master**:
   - On Jenkins Master, go to **Manage Jenkins** → **Manage Nodes and Clouds** → **New Node**.
   - Enter the Node name (`Partha-Jenkins-Slave-Agent`).
   - Select **Permanent Agent**, and configure:
     - **Remote root directory**: `/home/ec2-user/jenkins`
     - **Launch method**: **Launch agent via SSH**
     - **Host**: `partha.snehith-dev.com`
     - **Credentials**: Add the private SSH key for Jenkins Slave (`~/.ssh/jenkins_slave_key`).

---

## **Step 3: Set Up Nginx Reverse Proxy**

### **3.1 Install Nginx on the Jenkins Slave Node**

1. **Install Nginx**:

   ```bash
   sudo yum install nginx -y
   sudo systemctl start nginx
   sudo systemctl enable nginx
   ```

### **3.2 Configure Reverse Proxy for Ports 5000 and 8080**

1. **Edit the Nginx configuration** file:

   ```bash
   sudo vim /etc/nginx/nginx.conf
   ```

2. **Add the Reverse Proxy Configuration** for **Frontend (port 8080)** and **Backend (port 5000)**:

   ```nginx
   server {
       listen 80;
       server_name partha.snehith-dev.com;

       # Reverse Proxy to Jenkins Frontend on port 8080
       location / {
           proxy_pass http://localhost:8080;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       }

       # Reverse Proxy to Backend API on port 5000
       location /api/tasks {
           proxy_pass http://localhost:5000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       }
   }
   ```

3. **Restart Nginx** to apply the changes:

   ```bash
   sudo systemctl restart nginx
   ```

---

## **Step 4: Set Up Route 53 DNS Records**

### **4.1 Configure DNS Records**

1. **Go to AWS Route 53**:
   - Open the **Route 53** console in AWS.
   - Select the **hosted zone** for `snehith-dev.com`.

2. **Create DNS Records**:
   - **A Record for Jenkins Master**:
     - Name: `central-jenkins.snehith-dev.com`
     - Type: **A – IPv4 address**
     - Value: Public IP of Jenkins Master EC2.
   - **A Record for Jenkins Slave**:
     - Name: `partha.snehith-dev.com`
     - Type: **A – IPv4 address**
     - Value: Public IP of Jenkins Slave EC2.

3. **Test DNS Resolution**:
   - Ensure that `central-jenkins.snehith-dev.com` and `partha.snehith-dev.com` resolve correctly to your Jenkins Master and Slave EC2 IPs.

---

## **Step 5: Set Up ECR (Amazon Elastic Container Registry)**

### **5.1 Create ECR Repository**

1. **Create ECR Repository**:
   - Go to **ECR** in the AWS console.
   - Create a new repository named `partha-ecr`.

2. **Authenticate Docker to ECR**:
   - On both Jenkins Master and Slave nodes, log in to ECR using AWS CLI:

     ```bash
     aws configure
     ```

   - Authenticate Docker to ECR:

     ```bash
     aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 866934333672.dkr.ecr.us-east-1.amazonaws.com
     ```

---

## **Step 6: Create the Jenkins Pipeline**

### **6.1 Create a New Pipeline Job in Jenkins**

1. Go to the **Jenkins Dashboard** and click **New Item**.
2. Enter the **Item Name** (`partha-ecr-pipeline`), select **Pipeline**, and click **OK**.

### **6.2 Define the Jenkinsfile Pipeline**

In the **Pipeline** section of the new job:

- Use the following **Jenkinsfile** to build and push Docker images to ECR:

```groovy
pipeline {
    agent any
    parameters {
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'Which AWS Region to Deploy?')
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '866934333672', description: 'Which AWS Account to Deploy?')
    }
    environment {
        ECR_REPO_BASE = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/partha-ecr"
        BACKEND_IMAGE = "nodejs-cicd-frontend"
        FRONTEND_IMAGE = "nodejs-cicd-backend"
    }
    stages {
        stage('Fetch GitHub SSH Key') {
            steps {
                script {
                    // Fetch the secret from AWS Secrets Manager
                    def secretKey = sh(script: "aws secretsmanager get-secret-value --secret-id partha-jenkins-pipeline-secrets --query SecretString --output text", returnStdout: true).trim()
    
                    // Fetch and parse the secret in one step, avoiding intermediate logging
                    def SSHKey = sh(script: """
                        aws secretsmanager get-secret-value --secret-id partha-jenkins-pipeline-secrets --query SecretString --output text | jq -r '.\"partha-jenkins-pipeline-secrets\"'
                    """, returnStdout: true).trim()
    
                    // Clean up key (replace \\n with actual newline, remove extra spaces, etc.)
                    def cleanedKey = SSHKey.replaceAll('\\\\n', '\n').trim()
    
    
                    // Configure SSH environment
                    sh """
                        echo "$cleanedKey" > ~/.ssh/github
                        chmod 600 ~/.ssh/github
                        
                        echo -e "Host github.com\n  HostName github.com\n   IdentityFile ~/.ssh/github\n  StrictHostKeyChecking no\n  User git" > ~/.ssh/config
                        chmod 600 ~/.ssh/config
                    """
                }
            }
        }
        stage('Checkout') {
            steps {
                git branch: 'Development', credentialsId: '', url: 'git@github.com:pxkundu/JenkinsTask.git'
            }
        }
        stage('Build and Deploy') {
            steps {
                sh 'docker-compose up -d --build'
                sh 'docker ps -a'
            }
        }
        stage('Push to ECR') {
            steps {
                script {
                    sh 'docker tag ${BACKEND_IMAGE} ${ECR_REPO_BASE}:${BACKEND_IMAGE}'
                    sh 'docker tag ${FRONTEND_IMAGE} ${ECR_REPO_BASE}:${FRONTEND_IMAGE}'
                    sh 'docker push ${ECR_REPO_BASE}:${BACKEND_IMAGE}'
                    sh 'docker push ${ECR_REPO_BASE}:${FRONTEND_IMAGE}'
                }
            }
        }
    }
    post {
        always {
            echo 'Pipeline completed!'
        }
    }
}
```

### **6.3 Run the Pipeline**

- Trigger the pipeline by clicking **Build Now** in the Jenkins job.
- Monitor the console output to ensure the pipeline runs correctly.

---
