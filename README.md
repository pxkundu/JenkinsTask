# Week 3, Day 4 Simplified: SaaS Task Manager with Nginx Reverse Proxy

## Overview
A simplified, production-grade Task Manager with Nginx reverse proxy, deployed via a single Jenkinsfile and Docker Compose. Uses AWS ECR for images and S3 for logs/configs.

## Setup
- Replace `<your-username>`, `<your-bucket>`, `<account-id>` in `Jenkinsfile`.
- Push to GitHub and configure Jenkins with `Jenkinsfile`.
- Ensure EC2 instance `TaskManagerProd` is running with Docker and Docker Compose installed.
