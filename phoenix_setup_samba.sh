#!/bin/bash

# phoenix_setup_samba.sh
# Configures Samba file server on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_samba.sh [-n "network_name"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments (removed --no-ssl option)
NETWORK_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      NETWORK_NAME="$2"
      shift 2
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Ensure script runs as root using common function
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Initialize logging for consistent behavior
setup_logging

# Install Samba packages using common functions
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update && apt-get install -y samba samba-common-bin smbclient"
    echo "[$(date)] Installed Samba" >> "$LOGFILE"
  fi
}

# Create Samba user and set password with validation
configure_samba_user() {
  local samba_user="${SMB_USER:-admin}"

  # Check if system user exists before creating a Samba user
  if ! getent passwd "$samba_user" >/dev/null; then
    echo "Error: System user $samba_user does not exist." | tee -a "$LOGFILE"
    exit 1
  fi

  # If the Samba user doesn't already exist, prompt for a password and add it
  if ! pdbedit -L | grep -q "^$samba_user:"; then
    read -s -p "Enter password for Samba user $samba_user (min 8 chars, 1 special char): " SAMBA_PASSWORD
    echo

    # Validate password length and content
    if [[ ${#SAMBA_PASSWORD} -lt 8 || ! "$SAMBA_PASSWORD" =~ [^a-zA-Z0-9] ]]; then
      echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
      exit 1
    fi

    # Create the Samba user with a password
    echo "$SAMBA_PASSWORD" | smbpasswd -L -s -a "$samba_user" || {
      echo "Error: Failed to set Samba password for $samba_user." | tee -a "$LOGFILE"
      exit 1
    }

    echo "[$(date)] Created Samba user $samba_user with password." >> "$LOGFILE"
  else
    echo "[$(date)] Samba user $samba_user already exists, skipping creation." >> "$LOGFILE"
  fi
}

# Configure Samba server with workgroup and shares
configure_samba() {
  local workgroup="${NETWORK_NAME:-WORKGROUP}"
  local samba_user="${SMB_USER:-admin}"

  # Ensure base mount point directory exists
  mkdir -p "$MOUNT_POINT_BASE" || { echo "Error: Failed to create $MOUNT_POINT_BASE." | tee -a "$LOGFILE"; exit 1; }

  # Create dataset-specific directories and ensure they exist before configuring Samba shares
  local datasets=("shared-prod-data" "shared-prod-data-sync" "shared-backups")
  for dataset in "${datasets[@]}"; do
    mkdir -p "$MOUNT_POINT_BASE/$dataset" || { echo "Error: Failed to create $MOUNT_POINT_BASE/$dataset." | tee -a "$LOGFILE"; exit 1; }
  done

  # Configure Samba global settings and shares in /etc/samba/smb.conf
  cat << EOF > /etc/samba/smb.conf
[global]
   workgroup = $workgroup
   server string = %h Proxmox Samba Server
   log file = /var/log/samba/log.%m
   max log size = 50
   logging = file
   panic action = /usr/share/samba/panic-action %d
   map to guest = Bad User
   dns proxy = no

[shared-prod-data]
   path = $MOUNT_POINT_BASE/shared-prod-data
   writable = yes
   browsable = yes
   valid users = $samba_user
   create mask = 0644
   directory mask = 0755

[shared-prod-data-sync]
   path = $MOUNT_POINT_BASE/shared-prod-data-sync
   writable = yes
   browsable = yes
   valid users = $samba_user
   create mask = 0644
   directory mask = 0755

[shared-backups]
   path = $MOUNT_POINT_BASE/shared-backups
   writable = no
   browsable = yes
   valid users = $samba_user
EOF

  # Apply the updated Samba configuration and restart services
  retry_command "systemctl restart smbd nmbd"

  # Verify Samba services are running after restarting
  if ! systemctl is-active --quiet smbd && ! systemctl is-active --quiet nmbd; then
    echo "Error: Failed to start Samba services." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Configured and restarted Samba with shares for $samba_user" >> "$LOGFILE"

  # Check firewall rules before applying, avoiding redundancy with other scripts like phoenix_proxmox_initial_setup.sh
  if ! ufw status | grep -q "137/udp ALLOW Anywhere"; then
    retry_command "ufw allow Samba"
    echo "[$(date)] Updated firewall to allow Samba traffic" >> "$LOGFILE"
  else
    echo "[$(date)] Samba firewall rules already set, skipping." >> "$LOGFILE"
  fi
}

# Main execution using common functions
main() {
  check_root
  setup_logging
  install_samba
  configure_samba_user
  configure_samba

  echo "[$(date)] Completed Samba server configuration" >> "$LOGFILE"
}

main