#!/bin/bash

# setup_ssh_passwordless.sh
# Dynamically sets up passwordless SSH between two EC2 instances
# Run on the source instance to enable SSH to the target instance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        echo -e "${RED}Error: Invalid IP address: $ip${NC}"
        exit 1
    fi
}

# Function to validate file existence
validate_file() {
    local file=$1
    if [[ ! -f $file ]]; then
        echo -e "${RED}Error: File does not exist: $file${NC}"
        exit 1
    fi
}

# Function to prompt with default value
prompt_with_default() {
    local prompt=$1
    local default=$2
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

# Gather user inputs
echo "=== Passwordless SSH Setup Between EC2 Instances ==="
echo "This script configures passwordless SSH from a source EC2 instance to a target EC2 instance."
echo

# Source instance details
SOURCE_IP=$(prompt_with_default "Enter source instance private IP" "172.31.1.76")
validate_ip "$SOURCE_IP"
SOURCE_USER=$(prompt_with_default "Enter source instance username" "ec2-user")

# Target instance details
TARGET_PRIVATE_IP=$(prompt_with_default "Enter target instance private IP" "172.31.36.219")
validate_ip "$TARGET_PRIVATE_IP"
TARGET_PUBLIC_IP=$(prompt_with_default "Enter target instance public IP" "52.55.234.206")
validate_ip "$TARGET_PUBLIC_IP"
TARGET_USER=$(prompt_with_default "Enter target instance username" "ec2-user")

# SSH key details
echo "Do you want to (1) use an existing SSH key or (2) generate a new one?"
select KEY_OPTION in "Use existing" "Generate new"; do
    case $KEY_OPTION in
        "Use existing")
            KEY_PATH=$(prompt_with_default "Enter full path to existing private key" "/home/$SOURCE_USER/.ssh/id_rsa_partha")
            validate_file "$KEY_PATH"
            PUB_KEY_PATH="${KEY_PATH}.pub"
            validate_file "$PUB_KEY_PATH"
            break
            ;;
        "Generate new")
            KEY_PATH=$(prompt_with_default "Enter full path for new private key" "/home/$SOURCE_USER/.ssh/id_rsa_partha")
            PUB_KEY_PATH="${KEY_PATH}.pub"
            break
            ;;
        *) echo "Invalid option. Choose 1 or 2." ;;
    esac
done

# Temporary PEM key for initial target access
PEM_KEY=$(prompt_with_default "Enter full path to temporary PEM key for target access" "/home/$SOURCE_USER/my-key-pair.pem")
validate_file "$PEM_KEY"

# Confirm inputs
echo
echo "=== Input Summary ==="
echo "Source: $SOURCE_USER@$SOURCE_IP"
echo "Target: $TARGET_USER@$TARGET_PRIVATE_IP (public: $TARGET_PUBLIC_IP)"
echo "SSH Key: $KEY_PATH"
echo "PEM Key: $PEM_KEY"
read -p "Proceed with these settings? (y/n): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Aborted by user."
    exit 1
fi

# Step 1: Generate SSH key if needed
if [[ $KEY_OPTION == "Generate new" ]]; then
    echo "Generating new SSH key pair at $KEY_PATH..."
    ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N "" -q
    chmod 600 "$KEY_PATH"
    chmod 644 "$PUB_KEY_PATH"
    echo -e "${GREEN}Key pair generated successfully.${NC}"
fi

# Step 2: Set up SSH directory and permissions on source
echo "Configuring SSH directory on source instance..."
mkdir -p "/home/$SOURCE_USER/.ssh"
chmod 700 "/home/$SOURCE_USER/.ssh"
chown "$SOURCE_USER:$SOURCE_USER" "/home/$SOURCE_USER/.ssh"

# Step 3: Create SSH config for passwordless access
CONFIG_FILE="/home/$SOURCE_USER/.ssh/config"
echo "Configuring SSH config at $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<EOL
Host $TARGET_PRIVATE_IP
    HostName $TARGET_PRIVATE_IP
    User $TARGET_USER
    IdentityFile $KEY_PATH
EOL
chmod 600 "$CONFIG_FILE"
chown "$SOURCE_USER:$SOURCE_USER" "$CONFIG_FILE"
echo -e "${GREEN}SSH config created.${NC}"

# Step 4: Copy public key to target instance using PEM key
echo "Copying public key to target instance..."
TEMP_KEY=$(mktemp)
cat "$PUB_KEY_PATH" > "$TEMP_KEY"
scp -i "$PEM_KEY" "$TEMP_KEY" "$TARGET_USER@$TARGET_PUBLIC_IP:/tmp/public_key.pub"
ssh -i "$PEM_KEY" "$TARGET_USER@$TARGET_PUBLIC_IP" << 'EOF'
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cat /tmp/public_key.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    chown -R $TARGET_USER:$TARGET_USER ~/.ssh
    rm /tmp/public_key.pub
EOF
rm "$TEMP_KEY"
echo -e "${GREEN}Public key copied to target instance.${NC}"

# Step 5: Test passwordless SSH
echo "Testing passwordless SSH connection..."
if ssh -o BatchMode=yes "$TARGET_USER@$TARGET_PRIVATE_IP" "echo 'SSH successful'" 2>/dev/null; then
    echo -e "${GREEN}Passwordless SSH setup successful!${NC}"
    echo "You can now SSH from $SOURCE_USER@$SOURCE_IP to $TARGET_USER@$TARGET_PRIVATE_IP without a password."
else
    echo -e "${RED}Error: Passwordless SSH failed.${NC}"
    echo "Check:"
    echo "- Target instance's /home/$TARGET_USER/.ssh/authorized_keys contains the public key."
    echo "- Security group allows SSH (port 22) from $SOURCE_IP."
    echo "- Permissions on ~/.ssh and authorized_keys on target."
    exit 1
fi

# Step 6: Instructions for next steps
echo
echo "=== Next Steps ==="
echo "1. Verify SSH: ssh $TARGET_USER@$TARGET_PRIVATE_IP"
echo "2. Use in Ansible by updating inventory (e.g., hosts.ini):"
echo "   [$TARGET_PRIVATE_IP]"
echo "   ansible_host=$TARGET_PRIVATE_IP ansible_user=$TARGET_USER ansible_ssh_private_key_file=$KEY_PATH"
echo "3. Save this script to your repository for reuse."
