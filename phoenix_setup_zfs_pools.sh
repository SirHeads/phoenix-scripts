#!/bin/bash

# phoenix_setup_zfs_pools.sh
# Configures ZFS pools on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_pools.sh [-d "data_drive"] [-l "log_drive"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d)
      DATA_DRIVE="$2"
      shift 2
      ;;
    -l)
      LOG_DRIVE="$2"
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

# Check if data and log drives are specified, and verify they're not in use by another pool
check_available_drives() {
  local drive="$1"

  # Only exclude common system disks (sda and vda) to avoid excluding potentially valid disks
  if [[ "$drive" =~ ^(sd[a-z]|vd[a-z])$ ]]; then
    echo "Error: Drive $drive is either a system disk or invalid." | tee -a "$LOGFILE"
    exit 1
  fi

  # Check if the drive is already in use by another ZFS pool using zpool status
  if lsblk -o MOUNTPOINT | grep -q "/$drive"; then
    echo "Error: Drive $drive appears to be mounted or in use." | tee -a "$LOGFILE"
    exit 1
  fi

  # Verify the drive isn't part of an existing ZFS pool (avoid improper piping)
  if zpool status | grep -q "^[[:space:]]*$drive "; then
    echo "Error: Drive $drive is already in use by another ZFS pool." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Verified that drive $drive is available for use" >> "$LOGFILE"
}

# Create a ZFS pool and datasets using common functions
create_zfs_pools() {
  local pool_name="rpool"

  if zfs_pool_exists "$pool_name"; then
    echo "Pool $pool_name already exists, skipping creation." | tee -a "$LOGFILE"
  else
    retry_command "zpool create -f $pool_name $DATA_DRIVE"
    echo "[$(date)] Created ZFS pool: $pool_name on $DATA_DRIVE" >> "$LOGFILE"

    # Add a log device if specified and it's not already in use by another pool
    if [[ -n "$LOG_DRIVE" ]]; then
      check_available_drives "$LOG_DRIVE"
      retry_command "zpool add $pool_name log $LOG_DRIVE"
      echo "[$(date)] Added log device: $LOG_DRIVE to pool: $pool_name" >> "$LOGFILE"
    fi

    # Create datasets for the pool using the ZFS_DATASET_LIST from phoenix_config.sh
    mkdir -p /mnt/pve || { echo "Error: Failed to create /mnt/pve directory." | tee -a "$LOGFILE"; exit 1; }

    IFS=',' read -r -a datasets <<< "$ZFS_DATASET_LIST"
    for dataset in "${datasets[@]}"; do
      create_zfs_dataset "$pool_name" "$dataset" "/mnt/pve/$dataset"
      echo "[$(date)] Created ZFS dataset: $pool_name/$dataset with mountpoint /mnt/pve/$dataset" >> "$LOGFILE"
    done
  fi
}

# Main execution using common functions
main() {
  check_root
  setup_logging

  if [[ -z "$DATA_DRIVE" ]]; then
    read -p "Enter the data drive for ZFS pool (e.g., sdb): " DATA_DRIVE
  fi

  check_available_drives "$DATA_DRIVE"

  # Prompt for log drive only if not provided in command-line arguments
  if [[ -z "$LOG_DRIVE" ]]; then
    read -p "Enter the log drive for ZFS pool (optional, e.g., sdc): " LOG_DRIVE
  fi

  install_zfs_packages
  create_zfs_pools

  echo "[$(date)] Completed ZFS pool setup with $pool_name" >> "$LOGFILE"
}

main