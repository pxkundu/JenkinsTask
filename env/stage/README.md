# Terraform Project Environment explained

This repository contains a Terraform project for provisioning infrastructure. The project is organized to support multiple environments (e.g., development and staging) using a modular structure.

## Project Structure

```
.
├── README.md                # Project documentation (this file)
├── env/                     # Environment-specific configurations
│   ├── dev/                 # Development environment configuration
│   │   ├── main.tf          # Core Terraform configuration for dev
│   │   ├── outputs.tf       # Output definitions for dev
│   │   ├── terraform.tfvars # Variable values specific to dev
│   │   └── variables.tf     # Variable definitions for dev
│   └── stage/               # Staging environment configuration
├── files/                   # Static files and scripts used in the infrastructure
│   ├── Dockerfile           # Docker configuration file
│   ├── index.html           # Sample HTML file (e.g., for a web server)
│   ├── nginx.conf           # NGINX configuration file
│   ├── setup.sh             # Setup script for provisioning
│   └── user_data.sh         # User data script for EC2 instances
└── modules/                 # Reusable Terraform modules
    └── ec2/                 # EC2-specific module
        ├── main.tf          # EC2 resource definitions
        ├── outputs.tf       # EC2 module outputs
        └── variables.tf     # EC2 module variables
```

## Environment Folders

The `env/` directory contains subdirectories for different environments, each with its own Terraform configuration. This allows for environment-specific settings while reusing shared modules.

### `env/dev/`
- **Purpose**: This folder contains the Terraform configuration for the **development environment**. It is used to deploy and test infrastructure in a non-production setting.
- **Contents**:
  - `main.tf`: Defines the resources and modules used in the dev environment.
  - `outputs.tf`: Specifies outputs (e.g., IP addresses, resource IDs) for the dev environment.
  - `terraform.tfvars`: Provides variable values specific to dev (e.g., smaller instance sizes, dev-specific tags).
  - `variables.tf`: Declares variables used in the dev configuration.
- **Usage**: Run `terraform` commands from this directory to manage the dev environment.

### `env/stage/`
- **Purpose**: This folder contains the Terraform configuration for the **staging environment**. It is used to deploy a pre-production setup that mirrors production more closely than dev, allowing for testing and validation.
- **Contents**: (Currently empty, but typically mirrors `dev/` with its own `main.tf`, `outputs.tf`, `terraform.tfvars`, and `variables.tf`.)
- **Usage**: Run `terraform` commands from this directory to manage the staging environment.

## Getting Started

1. **Prerequisites**:
   - Install [Terraform](https://www.terraform.io/downloads.html).
   - Configure your cloud provider credentials (e.g., AWS CLI).

2. **Initialize an Environment**:
   - Navigate to the desired environment folder (e.g., `cd env/dev`).
   - Run `terraform init` to download provider plugins and modules.

3. **Deploy the Infrastructure**:
   - Run `terraform plan` to preview changes.
   - Run `terraform apply` to provision the resources.

4. **Clean Up**:
   - Run `terraform destroy` to remove all resources in the environment.

## Additional Notes
- The `modules/` directory contains reusable Terraform modules (e.g., `ec2`) that are called from environment-specific configurations.
- The `files/` directory includes scripts and configuration files (e.g., `user_data.sh`) that are referenced in Terraform resources like EC2 instances.
- Add environment-specific `.tfvars` files to customize deployments without modifying the core `.tf` files.

---

