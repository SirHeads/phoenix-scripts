#!/bin/bash

# phoenix_create_admin_user.sh
# Creates an admin user on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_create_admin_user.sh [-u username] [-p password] [-s ssh_public_key]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
while getopts ":u:p:s:" opt; do
  case ${opt} in
    u )
      USERNAME=$OPTARG
      ;;
    p )
      PASSWORD=$OPTARG
      ;;
    s )
      SSH_PUBLIC_KEY=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" | tee -a "$LOGFILE"
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Initialize logging
setup_logging

# Prompt for username if not provided
prompt_for_username() {
  DEFAULT_USERNAME="adminuser"
  if [[ -z "$USERNAME" ]]; then
    read -p "Enter new admin username [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  fi
  # Validate the username format
  if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo "Error: Username must start with a letter or number and can only contain letters, numbers, hyphens, or underscores." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create system user with password using common functions
create_user() {
  if id -u "$USERNAME" >/dev/null 2>&1; then
    echo "User $USERNAME already exists. Skipping user creation." | tee -a "$LOGFILE"
  else
    # Prompt for password if not provided via -p
    if [[ -z "$PASSWORD" ]]; then
      read -s -p "Enter password for user $USERNAME (min 8 chars, 1 special char): " PASSWORD
      echo
    fi
    # Validate password format (at least one special character and minimum length)
    if [[ ! "$PASSWORD" =~ [[:punct:]] && ${#PASSWORD} -lt 8 ]]; then
      echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
      exit 1
    fi

    # Create user with home directory and set password using common function
    retry_command "useradd -m -s /bin/bash $USERNAME && echo '$USERNAME:$PASSWORD' | chpasswd"

    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to create user or set password. Check system password policies." | tee -a "$LOGFILE"
      exit 1
    fi

    echo "[$(date)] Created user $USERNAME with password" >> "$LOGFILE"
  fi
}

# Add user to sudo group using common function and verify /etc/sudoers configuration
setup_sudo() {
  # Check if the sudo group exists, create it if not
  if ! getent group sudo >/dev/null; then
    retry_command "groupadd sudo"
  fi

  # Ensure user is added to the sudo group
  add_user_to_group "$USERNAME" "sudo"

  # Verify sudoers configuration for the sudo group
  SUDOERS_LINE='%sudo ALL=(ALL:ALL) ALL'
  if ! grep -Fx "$SUDOERS_LINE" /etc/sudoers; then
    echo "$SUDOERS_LINE" >> /etc/sudoers || { echo "Error: Failed to configure sudo group in /etc/sudoers." | tee -a "$LOGFILE"; exit 1; }
    echo "[$(date)] Updated /etc/sudoers with sudo group configuration" >> "$LOGFILE"
  else
    echo "[$(date)] Sudoers configuration for sudo group already exists, skipping" >> "$LOGFILE"
  fi
}

# Set up SSH key (if provided) with validation
setup_ssh_key() {
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    # Validate the SSH public key format
    if ! [[ "$SSH_PUBLIC_KEY" =~ ^(ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|ed25519) ]]; then
      echo "Error: Invalid SSH public key format. Key must start with 'ssh-rsa', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521', or 'ed25519'." | tee -a "$LOGFILE"
      exit 1
    fi

    mkdir -p "/home/$USERNAME/.ssh" || { echo "Error: Failed to create .ssh directory for user $USERNAME." | tee -a "$LOGFILE"; exit 1; }
    echo "$SSH_PUBLIC_KEY" > "/home/$USERNAME/.ssh/authorized_keys" || { echo "Error: Failed to write SSH key for user $USERNAME." | tee -a "$LOGFILE"; exit 1; }

    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh" || { echo "Error: Failed to set ownership of .ssh directory for user $USERNAME." | tee -a "$LOGFILE"; exit 1; }
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"

    echo "[$(date)] Set up SSH key for user $USERNAME" >> "$LOGFILE"
  fi
}

# Create Proxmox admin user and grant privileges using common functions
create_proxmox_admin() {
  if pveum user list | grep -q "^$USERNAME@pam\$"; then
    echo "Warning: Proxmox user $USERNAME@pam already exists. Checking permissions..." | tee -a "$LOGFILE"

    # Ensure the Administrator role is applied if missing
    if ! pveum acl list | grep -q "^ / \$USERNAME@pam .*Administrator\$"; then
      retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator"
      echo "[$(date)] Granted Proxmox admin role to user $USERNAME@pam" >> "$LOGFILE"
    else
      echo "[$(date)] Proxmox user $USERNAME@pam already has Administrator role" >> "$LOGFILE"
    fi
  else
    retry_command "pveum user add $USERNAME@pam"
    echo "[$(date)] Created Proxmox user $USERNAME@pam" >> "$LOGFILE"

    # Grant Proxmox admin privileges using common functions
    if ! pveum acl modify / -user "$USERNAME@pam" -role Administrator &>/dev/null; then
      echo "Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "$LOGFILE"
      exit 1
    fi

    echo "[$(date)] Created and configured Proxmox admin user '$USERNAME'" >> "$LOGFILE"
  fi
}

# Main execution using common functions
main() {
  check_root
  setup_logging
  prompt_for_username
  create_user
  setup_sudo
  setup_ssh_key
  create_proxmox_admin
}

main