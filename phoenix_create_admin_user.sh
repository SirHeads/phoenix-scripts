#!/bin/bash

# phoenix_create_admin_user.sh
# Creates a non-root Linux user with sudo and Proxmox admin privileges, sets up SSH key-based authentication
# Version: 1.4.2
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_create_admin_user.sh [--username <username>] [--password <password>] [--ssh-key <key>] [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Default values
DEFAULT_USERNAME="heads"
NO_REBOOT=0

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_PUBLIC_KEY="$2"
      shift 2
      ;;
    --no-reboot)
      NO_REBOOT=1
      shift
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Ensure sudo package and sudoers group exist
setup_sudo() {
  if ! check_package sudo; then
    retry_command "apt update"
    retry_command "apt install -y sudo"
    echo "[$(date)] Installed sudo package" >> "$LOGFILE"
  fi
  if ! getent group sudo &>/dev/null; then
    groupadd sudo || { echo "Error: Failed to create sudo group"; exit 1; }
    echo "[$(date)] Created sudo group" >> "$LOGFILE"
  fi
}

# Prompt for username if not provided
prompt_for_username() {
  if [[ -z "$USERNAME" ]]; then
    read -p "Enter new admin username [$DEFAULT_USERNAME]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USERNAME}
  fi
  if [[ -z "$USERNAME" ]]; then
    echo "Error: Username cannot be empty" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Validate and create user
create_user() {
  if getent passwd "$USERNAME" &>/dev/null; then
    echo "Warning: User $USERNAME already exists, skipping user creation" | tee -a "$LOGFILE"
    return 0
  fi

  # Prompt for password if not provided
  if [[ -z "$PASSWORD" ]]; then
    read -s -p "Enter password for $USERNAME (min 8 chars, 1 special char): " PASSWORD
    echo
  fi
  if [[ ${#PASSWORD} -lt 8 || ! $PASSWORD =~ [^a-zA-Z0-9] ]]; then
    echo "Error: Password must be at least 8 characters long and contain at least one special character" | tee -a "$LOGFILE"
    exit 1
  fi

  # Create user with home directory and set password
  useradd -m -s /bin/bash "$USERNAME" || { echo "Error: Failed to create user $USERNAME"; exit 1; }
  echo "$USERNAME:$PASSWORD" | chpasswd || { echo "Error: Failed to set password for user $USERNAME"; exit 1; }

  # Add user to sudo group
  usermod -aG sudo "$USERNAME" || { echo "Error: Failed to add user $USERNAME to sudo group"; exit 1; }

  # Set up SSH key (if provided)
  if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    mkdir -p "/home/$USERNAME/.ssh"
    echo "$SSH_PUBLIC_KEY" > "/home/$USERNAME/.ssh/authorized_keys" || { echo "Error: Failed to add SSH key for user $USERNAME"; exit 1; }
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh" || { echo "Error: Failed to set ownership of .ssh directory for user $USERNAME"; exit 1; }
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
  fi

  # Create Proxmox admin user
  if ! pveum user add "$USERNAME@pam" &>/dev/null; then
    echo "Error: Failed to create Proxmox user $USERNAME@pam" | tee -a "$LOGFILE"
    exit 1
  fi

  # Grant Proxmox admin privileges
  if ! pveum acl modify / -user "$USERNAME@pam" -role Administrator &>/dev/null; then
    echo "Error: Failed to grant Proxmox admin role to user $USERNAME@pam" | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Created and configured Proxmox admin user '$USERNAME'" >> "$LOGFILE"
}

# Update and upgrade system
update_system() {
  retry_command "apt-get update"
  retry_command "apt-get upgrade -y"
  retry_command "proxmox-boot-tool refresh"
  retry_command "update-initramfs -u"
  echo "[$(date)] System updated, upgraded, and initramfs refreshed" >> "$LOGFILE"
}

# Main execution
check_root
setup_sudo
prompt_for_username
create_user
update_system

echo "Setup complete for admin user '$USERNAME'."
echo "- SSH access: ssh $USERNAME@10.0.0.13"
echo "- Proxmox VE web interface: https://10.0.0.13:8006"
if [[ $NO_REBOOT -eq 0 ]]; then
  read -t 60 -p "Reboot now? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
  if [[ -z "$REBOOT_CONFIRMATION" || "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    echo "Rebooting system..."
    reboot
  else
    echo "Please reboot manually to apply changes."
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually."
fi
echo "[$(date)] Completed phoenix_create_admin_user.sh" >> "$LOGFILE"