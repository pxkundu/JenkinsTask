#!/bin/bash

# Stop and remove any existing container
docker rm -f app-container || true

# Run the container
docker run -d --name app-container -p 8080:80 my-app-image

# Verify the container is running
docker ps -a
