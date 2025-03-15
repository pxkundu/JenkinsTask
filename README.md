# Week 3, Day 4 Simplified: SaaS Task Manager with Nginx Reverse Proxy

## Overview
A minimal, production-grade Task Manager with frontend (8080) and backend (5000) behind an Nginx reverse proxy (80). Built on a Jenkins slave via docker-compose from Git repo Dockerfiles with unique build tags, pushed as latest to ECR, with ECR fallback on failure.

## Setup
- Replace `<your-username>`, `<account-id>` in `Jenkinsfile` and `docker-compose.yml`.
- Push to GitHub and configure Jenkins with `Jenkinsfile`.
- Ensure slave `docker-slave-east` has Docker and Docker Compose installed.
- AWS Cloud must be configured in Jenkins for ECR access.
