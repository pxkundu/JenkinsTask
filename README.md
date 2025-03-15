# Week 3, Day 4 Alternative: Simplified SaaS Task Manager with Nginx Reverse Proxy

## Overview
A production-grade version of the Task Manager with Nginx as a reverse proxy, running frontend (8080) and backend (5000) in Docker, deployed via Jenkins Master-Slave architecture to AWS ECR and EC2.

## Setup
- Replace `<your-username>`, `<your-bucket>`, `<account-id>` in files.
- Push `task-manager` and `pipeline-lib` to GitHub.
- Run `setup-scripts/deploy-instance.sh` to launch EC2.
- Configure Jenkins with `Jenkinsfile`.
