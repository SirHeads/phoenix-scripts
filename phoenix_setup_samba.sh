#!/bin/bash

# phoenix_setup_samba.sh
# Configures Samba file server on Proxmox VE
# Version: 1.0.4
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_samba.sh [-n "network_name"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
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

# Ensure script runs as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Initialize logging
setup_logging

# Install Samba packages
install_samba() {
  if ! check_package samba; then
    retry_command "apt-get update && apt-get install -y samba samba-common-bin smbclient"
    echo "[$(date)] Installed Samba" >> "$LOGFILE"
  fi
}

# Create Samba user and set password
configure_samba_user() {
  local samba_user="${SMB_USER:-admin}"

  if ! getent passwd "$samba_user" >/dev/null; then
    echo "Error: System user $samba_user does not exist." | tee -a "$LOGFILE"
    exit 1
  fi

  if ! pdbedit -L | grep -q "^$samba_user:"; then
    read -s -p "Enter password for Samba user $samba_user (min 8 chars, 1 special char): " SAMBA_PASSWORD
    echo

    if [[ ${#SAMBA_PASSWORD} -lt 8 || ! "$SAMBA_PASSWORD" =~ [^a-zA-Z0-9] ]]; then
      echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
      exit 1
    fi

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

  mkdir -p "$MOUNT_POINT_BASE" || { echo "Error: Failed to create $MOUNT_POINT_BASE." | tee -a "$LOGFILE"; exit 1; }

  local datasets=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "quickOS/shared-backups" "fastData/shared-test-data" "fastData/shared-iso" "fastData/shared-bulk-data")
  for dataset in "${datasets[@]}"; do
    local mountpoint="$MOUNT_POINT_BASE/$(basename $dataset)"
    mkdir -p "$mountpoint" || { echo "Error: Failed to create $mountpoint." | tee -a "$LOGFILE"; exit 1; }
  done

  if [[ -f /etc/samba/smb.conf ]]; then
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%F_%H-%M-%S)" || {
      echo "Error: Failed to back up /etc/samba/smb.conf" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Backed up /etc/samba/smb.conf" >> "$LOGFILE"
  fi

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
   force create mode = 0644
   force directory mode = 0755

[shared-prod-data-sync]
   path = $MOUNT_POINT_BASE/shared-prod-data-sync
   writable = yes
   browsable = yes
   valid users = $samba_user
   create mask = 0644
   directory mask = 0755
   force create mode = 0644
   force directory mode = 0755

[shared-backups]
   path = $MOUNT_POINT_BASE/shared-backups
   writable = no
   browsable = yes
   valid users = $samba_user

[shared-test-data]
   path = $MOUNT_POINT_BASE/shared-test-data
   writable = yes
   browsable = yes
   valid users = $samba_user
   create mask = 0644
   directory mask = 0755
   force create mode = 0644
   force directory mode = 0755

[shared-iso]
   path = $MOUNT_POINT_BASE/shared-iso
   writable = no
   browsable = yes
   valid users = $samba_user

[shared-bulk-data]
   path = $MOUNT_POINT_BASE/shared-bulk-data
   writable = yes
   browsable = yes
   valid users = $samba_user
   create mask = 0644
   directory mask = 0755
   force create mode = 0644
   force directory mode = 0755
EOF

  retry_command "systemctl restart smbd nmbd"

  if ! systemctl is-active --quiet smbd || ! systemctl is-active --quiet nmbd; then
    echo "Error: Failed to start Samba services." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Configured and restarted Samba with shares for $samba_user" >> "$LOGFILE"

  if ! ufw status | grep -q "137/udp ALLOW Anywhere"; then
    retry_command "ufw allow Samba"
    echo "[$(date)] Updated firewall to allow Samba traffic" >> "$LOGFILE"
  else
    echo "[$(date)] Samba firewall rules already set, skipping." >> "$LOGFILE"
  fi
}

# Configure LXC bind mounts
configure_lxc_bind_mounts() {
  local datasets=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "fastData/shared-test-data" "fastData/shared-bulk-data")
  for dataset in "${datasets[@]}"; do
    local mountpoint="/mnt/pve/$(basename $dataset)"
    if zfs_dataset_exists "$dataset"; then
      # Note: Actual LXC bind mount configuration requires per-container setup in Proxmox
      echo "[$(date)] LXC bind mount configuration for $dataset should use discard,noatime options in Proxmox LXC config" >> "$LOGFILE"
    fi
  done
}

# Main execution
main() {
  check_root
  setup_logging
  install_samba
  configure_samba_user
  configure_samba
  configure_lxc_bind_mounts

  echo "[$(date)] Completed Samba server configuration" >> "$LOGFILE"
}

main