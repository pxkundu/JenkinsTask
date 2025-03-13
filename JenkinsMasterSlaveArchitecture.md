# **Complete Guide to Set Up Jenkins Master-Slave Architecture on Amazon EC2 with Docker Build Pipeline**

## **Overview**
This document mentions the process of setting up a **Jenkins Master-Slave architecture** on **Amazon EC2** with **Java 17** and configuring Jenkins to **build a Docker image** for **Nginx**. We’ll also cover the steps to set up a **Jenkins slave node** (EC2 instance) to offload the build process and how to connect Jenkins with GitHub using SSH keys.

---

## **Prerequisites**
- **Amazon EC2 Instance** (Amazon Linux 2) as the **Jenkins Master**.
- **Amazon EC2 Instance** as the **Jenkins Slave**.
- **SSH access** to both the EC2 instances.
- **Root or sudo privileges** on the EC2 instances.

---

## **Step 1: Set Up Jenkins Master Node on Amazon EC2**

### **1.1 Connect to EC2 Instance**

First, SSH into your EC2 instance that will act as the **Jenkins Master**.

```bash
ssh -i your-key.pem ec2-user@3.83.26.46
```

Replace `your-key.pem` with your actual private key and `ec2-user@3.83.26.46` with your EC2 instance's public IP.

---

### **1.2 Update the EC2 Instance**

Before starting the Jenkins installation, make sure your EC2 instance is up-to-date.

```bash
sudo yum update -y
```

---

### **1.3 Install Java 17 (Jenkins Requirement)**

Jenkins requires **Java 17** to run. Install the OpenJDK 17 package:

```bash
sudo yum install java-17-openjdk-devel -y
```

Verify the installation:

```bash
java -version
```

You should see:

```
openjdk version "17.0.1" 2021-10-19
OpenJDK Runtime Environment (build 17.0.1+12-39)
OpenJDK 64-Bit Server VM (build 17.0.1+12-39, mixed mode)
```

---

### **1.4 Add Jenkins Repository and Install Jenkins**

1. **Import Jenkins GPG Key**:

   ```bash
   sudo curl -fsSL https://pkg.jenkins.io/redhat/jenkins.io.key | sudo tee /etc/pki/rpm-gpg/jenkins.io.key
   ```

2. **Add Jenkins Repository**:

   ```bash
   sudo sh -c 'echo "[jenkins]
   name=Jenkins
   baseurl=http://pkg.jenkins.io/redhat/jenkins-2.332.3-1.1/centos/
   gpgcheck=1
   enabled=1" > /etc/yum.repos.d/jenkins.repo'
   ```

3. **Install Jenkins**:

   ```bash
   sudo yum install jenkins -y
   ```

---

### **1.5 Start Jenkins Service**

1. **Start Jenkins**:

   ```bash
   sudo systemctl start jenkins
   ```

2. **Enable Jenkins to Start on Boot**:

   ```bash
   sudo systemctl enable jenkins
   ```

---

### **1.6 Open Jenkins Port in the EC2 Security Group**

Make sure your EC2 instance allows inbound traffic on **port 8080** (the default port Jenkins runs on):

1. Go to the **EC2 Console**, select your instance, and click on the **Security Group** associated with the instance.
2. Edit inbound rules to allow **port 8080**:
   - **Type**: Custom TCP Rule
   - **Port Range**: 8080
   - **Source**: Anywhere (0.0.0.0/0) or specific IP for security.

---

### **1.7 Access Jenkins Web Interface**

Open your browser and go to:

```
http://3.83.26.46:8080
```

You will be prompted for the **Jenkins unlock key**.

---

### **1.8 Retrieve the Jenkins Unlock Key**

Run the following command on the Jenkins Master to retrieve the unlock key:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Copy the output and paste it into the web interface to unlock Jenkins.

---

### **1.9 Complete the Jenkins Setup**

1. Install **recommended plugins** during the setup.
2. Create the **admin user** for Jenkins access.

Now Jenkins is up and running at `http://3.83.26.46:8080/`.

---

## **Step 2: Set Up Jenkins Slave Node (Amazon EC2)**

### **2.1 Launch EC2 Slave Instance**

1. **Launch an EC2 instance** using the **Amazon Linux 2 AMI**.
2. Configure the instance type (e.g., **t2.micro**) and security group to allow **SSH (port 22)**.
3. Once the EC2 instance is running, note down the **Public IP** (e.g., `54.92.165.176`).

---

### **2.2 Connect to EC2 Slave Instance**

SSH into the **EC2 Slave** instance:

```bash
ssh -i your-key.pem ec2-user@54.92.165.176
```

---

### **2.3 Install Docker and Java 17 on Slave Node**

1. **Install Docker**:

   ```bash
   sudo yum install docker -y
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

2. **Install Java 17**:

   ```bash
   sudo yum install java-17-openjdk-devel -y
   ```

---

## **Step 3: Set Up SSH Keys for Jenkins Master-Slave Connection**

### **3.1 Generate SSH Key Pair on Jenkins Master**

Generate an SSH key pair on the Jenkins Master node:

```bash
ssh-keygen -t rsa -b 4096 -C "jenkins-master" -f ~/.ssh/jenkins_slave_key
```

This will generate:
- `~/.ssh/jenkins_slave_key` (private key)
- `~/.ssh/jenkins_slave_key.pub` (public key)

---

### **3.2 Copy SSH Public Key to Slave Node**

Copy the public key to the **Slave EC2 instance** to enable SSH connection without a password.

```bash
ssh-copy-id -i ~/.ssh/jenkins_slave_key.pub ec2-user@54.92.165.176
```

You will be prompted to enter the password for the **ec2-user** on the slave node.

---

### **3.3 Verify SSH Connection from Jenkins Master to Slave**

Test the SSH connection from the Jenkins Master to the Slave node:

```bash
ssh -i ~/.ssh/jenkins_slave_key ec2-user@54.92.165.176
```

You should be logged into the Slave EC2 instance without entering a password.

---

### **3.4 Add Slave Node to Jenkins Master**

1. **Log into Jenkins Master**:
   - Go to `http://3.83.26.46:8080`.
2. **Go to Manage Jenkins > Manage Nodes and Clouds**.
3. **Click "New Node"** and enter a name (e.g., `Partha-Jenkins-Slave-Agent`).
4. **Configure the Slave Node**:
   - **Remote root directory**: `/home/ec2-user/jenkins`
   - **Labels**: `Partha-Jenkins-Slave-Agent`
   - **Launch method**: **Launch agent via SSH**.
   - **Host**: `54.92.165.176` (Slave node IP).
   - **Credentials**: Add the private key (`~/.ssh/jenkins_slave_key`) under SSH credentials.
5. **Test Connection** and click **Save**.

---

## **Step 4: Create a Jenkins Pipeline to Build Docker Image for Nginx**

### **4.1 Create a New Pipeline Job in Jenkins**

1. **Create a new item** in Jenkins:
   - Name: `nginx-docker-build`
   - Type: **Pipeline**.
   
2. **Configure the Pipeline**:
   - Scroll down to the **Pipeline** section and select **Pipeline script**.
   - Enter the following pipeline script:

```groovy
pipeline {
    agent { label 'Partha-Jenkins-Slave-Agent' }  // Use the EC2 slave node labeled 'Partha-Jenkins-Slave-Agent'

    environment {
        GIT_URL = 'git@github.com:pxkundu/JenkinsTask.git'
        GIT_BRANCH = 'Development'
        DOCKER_IMAGE_NAME = 'nginx-docker-image'
    }

    stages {
        stage('Clone Repository') {
            steps {
                // Clone the repository from GitHub using SSH (ensure Jenkins has the proper SSH key configured)
                git url: GIT_URL, branch: GIT_BRANCH
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Build the Docker image for Nginx
                    sh 'docker build -t $DOCKER_IMAGE_NAME .'
                }
            }
        }
    }

    post {
        always {
            // Clean up Docker system after build (optional)
            sh 'docker system prune -f'
        }
    }
}
```

---

### **4.2 Configure GitHub SSH Key in Jenkins**

To enable Jenkins to clone the repository from GitHub using SSH, add the SSH key to Jenkins credentials:

1. **Go to Manage Jenkins

 > Manage Credentials**.
2. **Add a new SSH key**:
   - Add the private SSH key you used earlier (`~/.ssh/jenkins_slave_key`).
   - Name the credentials (e.g., `GitHub-SSH-Key`).
3. Ensure that Jenkins can access GitHub using this SSH key.

---

### **4.3 Run the Jenkins Pipeline**

Now, run the pipeline by clicking **Build Now** on the `nginx-docker-build` job. Jenkins will:
- Clone the repository from GitHub.
- Build the Docker image for Nginx.
- Clean up the Docker system after the build completes.

---
