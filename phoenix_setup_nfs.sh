#!/bin/bash

# phoenix_setup_nfs.sh
# Installs and configures NFS server on Proxmox VE
# Version: 1.0.6
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Ensure script runs as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check for pvesm availability
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "Error: pvesm command not found. Ensure this script is running on a Proxmox VE system." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Verified pvesm availability" >> "$LOGFILE"
}

# Initialize logging
setup_logging

# Prompt for network subnet
prompt_for_subnet() {
  read -p "Enter network subnet for NFS (default: ${DEFAULT_SUBNET}): " NFS_SUBNET
  NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
  if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "Error: Invalid subnet format: $NFS_SUBNET" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check network connectivity
check_network() {
  echo "Checking network connectivity..." | tee -a "$LOGFILE"

  if ! ping -c 1 localhost >/dev/null 2>&1; then
    echo "Warning: Hostname 'localhost' does not resolve to 127.0.0.1. Check /etc/hosts." | tee -a "$LOGFILE"
  fi

  if [[ -n "$IP_ADDRESS" ]]; then
    PROXMOX_NFS_SERVER="$IP_ADDRESS"
    export PROXMOX_NFS_SERVER
  fi

  check_network_connectivity "$PROXMOX_NFS_SERVER"
  check_interface_in_subnet "$NFS_SUBNET"
  check_internet_connectivity
}

# Install required NFS packages
install_prerequisites() {
  if ! check_package nfs-kernel-server; then
    retry_command "apt-get update && apt-get install -y nfs-kernel-server nfs-common ufw"
    echo "[$(date)] Installed NFS prerequisites" >> "$LOGFILE"
  fi

  if ! systemctl is-active --quiet nfs-kernel-server; then
    retry_command "systemctl start nfs-kernel-server"
    retry_command "systemctl enable nfs-kernel-server"
    echo "[$(date)] Started and enabled nfs-kernel-server" >> "$LOGFILE"
  fi
}

# Configure NFS server
configure_nfs() {
  echo "Configuring NFS exports..." | tee -a "$LOGFILE"

  mkdir -p /mnt/pve || { echo "Error: Failed to create /mnt/pve" | tee -a "$LOGFILE"; exit 1; }

  for dataset in "${NFS_DATASET_LIST[@]}"; do
    local mountpoint="/mnt/pve/$(basename $dataset)"
    mkdir -p "$mountpoint"

    local pool=$(dirname $dataset)
    local dataset_name=$(basename $dataset)
    if ! zfs_dataset_exists "$pool/$dataset_name"; then
      echo "Error: Dataset $pool/$dataset_name does not exist, skipping NFS export" | tee -a "$LOGFILE"
      continue
    fi

    local export_options="${NFS_DATASET_OPTIONS[$dataset]}"
    configure_nfs_export "$dataset" "$mountpoint" "$NFS_SUBNET" "$export_options"
  done

  verify_nfs_exports
}

# Main execution
main() {
  check_root
  setup_logging
  check_pvesm
  prompt_for_subnet
  check_network
  install_prerequisites
  configure_nfs

  echo "[$(date)] Completed NFS server configuration" >> "$LOGFILE"
}

main