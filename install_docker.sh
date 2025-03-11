#!/bin/bash

# Update package list
sudo yum update -y

# Install Docker using amazon-linux-extras
sudo amazon-linux-extras install docker -y

# Start Docker service
sudo systemctl start docker

# Enable Docker to start on boot
sudo systemctl enable docker

# Add the current user to the docker group
sudo usermod -aG docker $USER

# Verify Docker installation
docker --version
