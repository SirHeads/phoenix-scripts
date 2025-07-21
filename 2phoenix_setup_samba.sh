#!/bin/bash

# proxmox_setup_samba.sh
# Configures Samba file server on Proxmox VE
# Version: 1.0.2
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_samba.sh [--no-ssl] [-n "network_name"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
NO_SSL=0
NETWORK_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-ssl)
      NO_SSL=1
      shift
      ;;
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

# Install Samba packages using common functions
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update && apt-get install -y samba samba-common-bin smbclient"
    echo "[$(date)] Installed Samba" >> "$LOGFILE"
  fi
}

# Set up Samba configuration using common functions
configure_samba() {
  local workgroup="WORKGROUP"
  if [[ ! -z $NETWORK_NAME ]]; then
    workgroup="$NETWORK_NAME"
  fi

  # Create Samba user and set password using common function
  samba_user="${SMB_USER:-admin}"
  retry_command "smbpasswd -L -a \"$samba_user\""

  # Set up global configuration in /etc/samba/smb.conf using common functions
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
EOF

  # Set up shares in /etc/samba/smb.conf using common functions
  cat << EOF >> /etc/samba/smb.conf
[shared]
    path = $MOUNT_POINT_BASE/shared
    writable = yes
    browsable = yes
    valid users = $samba_user
    create mask = 0644
    directory mask = 0755

[shared-sync]
    path = $MOUNT_POINT_BASE/shared-sync
    writable = yes
    browsable = yes
    valid users = $samba_user
    create mask = 0644
    directory mask = 0755

[backups]
    path = $MOUNT_POINT_BASE/backups
    writable = no
    browsable = yes
    valid users = $samba_user
EOF

  # Restart Samba services using common functions
  retry_command "systemctl restart smbd nmbd"
  echo "[$(date)] Configured and restarted Samba" >> "$LOGFILE"

  # Set up firewall rules for Samba using common function
  set_firewall_rule "allow samba"
  echo "[$(date)] Updated firewall rules to allow Samba traffic" >> "$LOGFILE"
}

# Main execution using common functions
main() {
  check_root
  install_samba
  configure_samba
}

main