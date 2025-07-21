#!/bin/bash

# proxmox_setup_zfs_pools.sh
# Configures ZFS pools on Proxmox VE
# Version: 1.0.2
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_zfs_pools.sh [-d "data_drive"] [-l "log_drive"]
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

# Install ZFS packages using common functions
install_zfs_packages() {
  if ! check_package zfsutils-linux; then
    retry_command "apt-get update && apt-get install -y zfsutils-linux"
    echo "[$(date)] Installed ZFS utilities" >> "$LOGFILE"
  fi
}

# Check for available drives and prompt user if needed using common functions
check_available_drives() {
  echo "Checking available disks..." | tee -a "$LOGFILE"

  # List unpartitioned or unused disks
  lsblk_output=$(lsblk -no NAME,TYPE,SIZE,MODEL -e 7,11)
  echo "$lsblk_output" >> "$LOGFILE"
  while read -r line; do
    if [[ $line == *"disk"* && ! $line =~ "vda\|vdb\|vd*" ]]; then
      disk_name=$(echo $line | awk '{print $1}')
      echo "Found available disk: /dev/$disk_name" | tee -a "$LOGFILE"
      if [[ -z "$DATA_DRIVE" ]]; then
        read -p "Use this as data drive (y/n)? " response
        case $response in
          [Yy]* )
            DATA_DRIVE="/dev/$disk_name"
            ;;
          * )
            echo "Skipping disk /dev/$disk_name" | tee -a "$LOGFILE"
            ;;
        esac
      fi

      if [[ -z "$LOG_DRIVE" ]]; then
        read -p "Use this as log drive (y/n)? " response
        case $response in
          [Yy]* )
            LOG_DRIVE="/dev/$disk_name"
            ;;
          * )
            echo "Skipping disk /dev/$disk_name" | tee -a "$LOGFILE"
            ;;
        esac
      fi

      # If both drives are selected, break out of loop using common functions
      if [[ ! -z "$DATA_DRIVE" && ! -z "$LOG_DRIVE" ]]; then
        break
      fi
    fi
  done <<< "$lsblk_output"

  # Ensure drives were selected using common functions
  if [[ -z "$DATA_DRIVE" || -z "$LOG_DRIVE" ]]; then
    echo "Error: Both data and log drives must be specified." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create ZFS pools using common functions
create_zfs_pools() {
  local pool_name="rpool"

  # Check if the pool already exists using common function
  if zfs_pool_exists "$pool_name"; then
    echo "Pool $pool_name already exists, skipping creation." | tee -a "$LOGFILE"
  else
    retry_command "zpool create -f $pool_name $DATA_DRIVE"
    echo "[$(date)] Created ZFS pool: $pool_name on $DATA_DRIVE" >> "$LOGFILE"

    # Create log device if specified and not already attached to a pool using common function
    if [[ ! -z "$LOG_DRIVE" && ! zfs_pool_exists | grep -qv "^$pool_name\s" ]]; then
      retry_command "zpool add $pool_name log $LOG_DRIVE"
      echo "[$(date)] Added log device: $LOG_DRIVE to pool: $pool_name" >> "$LOGFILE"
    fi

    # Create datasets for the pool using common function
    create_zfs_datasets() {
      local dataset_list=("shared-prod-data" "shared-prod-data-sync" "shared-test-data" "shared-test-data-sync" "backups" "iso" "bulk-data")

      for dataset in "${dataset_list[@]}"; do
        retry_command "zfs create -o mountpoint=/mnt/pve/$dataset $pool_name/$dataset"
        echo "[$(date)] Created ZFS dataset: $pool_name/$dataset with mountpoint /mnt/pve/$dataset" >> "$LOGFILE"
      done
    }

    create_zfs_datasets
  fi

  # Create another pool for NFS if needed using common function
  local nfs_pool="quickOS"

  if zfs_pool_exists "$nfs_pool"; then
    echo "Pool $nfs_pool already exists, skipping creation." | tee -a "$LOGFILE"
  else
    retry_command "zpool create -f $nfs_pool $DATA_DRIVE"
    echo "[$(date)] Created ZFS pool: $nfs_pool on $DATA_DRIVE" >> "$LOGFILE"

    # Create datasets for the NFS pool using common function
    local nfs_dataset_list=("shared-prod-data" "shared-prod-data-sync")

    for dataset in "${nfs_dataset_list[@]}"; do
      retry_command "zfs create -o mountpoint=/quickOS/$dataset $nfs_pool/$dataset"
      echo "[$(date)] Created ZFS dataset: $nfs_pool/$dataset with mountpoint /quickOS/$dataset" >> "$LOGFILE"
    done
  fi
}

# Main execution using common functions
main() {
  check_root
  install_zfs_packages
  check_available_drives
  create_zfs_pools
}

main