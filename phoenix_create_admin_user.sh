#!/bin/bash

# phoenix_create_admin_user.sh
# Creates a system and Proxmox VE admin user with sudo privileges and optional SSH key configuration for the Phoenix server.
# Version: 1.2.0
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_create_admin_user.sh [-u username] [-p password] [-s ssh_public_key]

# Log file
LOGFILE="/var/log/proxmox_setup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Function to check if the script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$TIMESTAMP] Verified script is running as root" >> "$LOGFILE"
}

# Ensure log file exists and is writable
touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
chmod 644 "$LOGFILE"
echo "[$TIMESTAMP] Initialized logging for phoenix_create_admin_user.sh" >> "$LOGFILE"

# Function to execute commands with retries
retry_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "[$TIMESTAMP] Attempt $attempt/$max_attempts: $cmd" >> "$LOGFILE"
        eval $cmd
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Command succeeded: $cmd" >> "$LOGFILE"
            return 0
        fi
        echo "[$TIMESTAMP] Command failed, retrying ($attempt/$max_attempts): $cmd" >> "$LOGFILE"
        sleep 5
        ((attempt++))
    done
    echo "[$TIMESTAMP] Error: Command failed after $max_attempts attempts: $cmd" | tee -a "$LOGFILE"
    return 1
}

# Function to prompt for username if not provided
prompt_for_username() {
    DEFAULT_USERNAME="heads"
    if [[ -z "$USERNAME" ]]; then
        read -p "Enter new admin username [$DEFAULT_USERNAME]: " USERNAME
        USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    fi
    # Validate the username format
    if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        echo "Error: Username must start with a letter or number and can only contain letters, numbers, hyphens, or underscores." | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$TIMESTAMP] Set USERNAME to $USERNAME" >> "$LOGFILE"
}

# Function to prompt for password if not provided
prompt_for_password() {
    DEFAULT_PASSWORD="Kick@$$2025"
    if [[ -z "$PASSWORD" ]]; then
        read -s -p "Enter password for user $USERNAME (min 8 chars, 1 special char) [$DEFAULT_PASSWORD]: " PASSWORD
        echo
        PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    fi
    # Validate password format
    if [[ ! "$PASSWORD" =~ [[:punct:]] || ${#PASSWORD} -lt 8 ]]; then
        echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$TIMESTAMP] Set PASSWORD for user $USERNAME" >> "$LOGFILE"
}

# Function to set up SSH key (if provided)
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
        chmod 700 "/home/$USERNAME/.ssh" || { echo "Error: Failed to set permissions for .ssh directory." | tee -a "$LOGFILE"; exit 1; }
        chmod 600 "/home/$USERNAME/.ssh/authorized_keys" || { echo "Error: Failed to set permissions for authorized_keys." | tee -a "$LOGFILE"; exit 1; }

        echo "[$TIMESTAMP] Set up SSH key for user $USERNAME" >> "$LOGFILE"
    else
        echo "[$TIMESTAMP] No SSH public key provided, skipping SSH key setup" >> "$LOGFILE"
    fi
}

# Parse command-line arguments
while getopts "u:p:s:" opt; do
    case $opt in
        u) USERNAME="$OPTARG";;
        p) PASSWORD="$OPTARG";;
        s) SSH_PUBLIC_KEY="$OPTARG";;
        \?) echo "Invalid option: -$OPTARG" | tee -a "$LOGFILE"; exit 1;;
        :) echo "Option -$OPTARG requires an argument." | tee -a "$LOGFILE"; exit 1;;
    esac
done

# Main execution
check_root
prompt_for_username
prompt_for_password

# Create system user if it doesn't exist
if ! id "$USERNAME" >/dev/null 2>&1; then
    retry_command "useradd -m -s /bin/bash $USERNAME" || { echo "Error: Failed to create system user $USERNAME" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Created system user $USERNAME" >> "$LOGFILE"
    retry_command "echo \"$USERNAME:$PASSWORD\" | chpasswd" || { echo "Error: Failed to set password for $USERNAME" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Set password for system user $USERNAME" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] User $USERNAME already exists. Skipping user creation." >> "$LOGFILE"
fi

# Add user to sudo group
if ! getent group sudo >/dev/null; then
    retry_command "groupadd sudo" || { echo "Error: Failed to create sudo group" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Created sudo group" >> "$LOGFILE"
fi
retry_command "usermod -aG sudo $USERNAME" || { echo "Error: Failed to add $USERNAME to sudo group" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Added user $USERNAME to group sudo" >> "$LOGFILE"

# Configure sudoers
if ! grep -q "%sudo ALL=(ALL:ALL) ALL" /etc/sudoers; then
    echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers || { echo "Error: Failed to configure sudoers for sudo group" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Configured sudoers for sudo group" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] Sudoers configuration for sudo group already exists, skipping" >> "$LOGFILE"
fi

# Create Proxmox VE user
if pveum user list | grep -q "^$USERNAME@pam\$"; then
    echo "[$TIMESTAMP] Proxmox user $USERNAME@pam already exists, checking permissions" >> "$LOGFILE"
    if ! pveum acl list | grep -q "^ / $USERNAME@pam .*Administrator\$"; then
        retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || { echo "Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "$LOGFILE"; exit 1; }
        echo "[$TIMESTAMP] Granted Proxmox admin role to user $USERNAME@pam" >> "$LOGFILE"
    else
        echo "[$TIMESTAMP] Proxmox user $USERNAME@pam already has Administrator role" >> "$LOGFILE"
    fi
else
    retry_command "pveum user add $USERNAME@pam" || { echo "Error: Failed to create Proxmox user $USERNAME@pam" | tee -a "$LOGFILE"; exit 1; }
    retry_command "pveum acl modify / -user $USERNAME@pam -role Administrator" || { echo "Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Created Proxmox user $USERNAME@pam with Administrator role" >> "$LOGFILE"
fi

# Set up SSH key (if provided)
setup_ssh_key

echo "[$TIMESTAMP] Successfully completed phoenix_create_admin_user.sh" >> "$LOGFILE"
exit 0