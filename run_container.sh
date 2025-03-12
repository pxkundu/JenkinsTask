#!/bin/bash

# Stop and remove any existing container
docker rm -f node-app-container || true

# Run the container
docker run -d --name node-app-container -p 8080:80 node-app-jenkins

# Verify the container is running
docker ps -a
