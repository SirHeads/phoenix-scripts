#!/bin/bash

# proxmox_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.0.2
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_setup_zfs_datasets.sh [-p "pool_name"] [-d "dataset_list"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p)
      POOL_NAME="$2"
      shift 2
      ;;
    -d)
      DATASET_LIST="$2"
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

# Check if pool exists or create it using common function
check_or_create_pool() {
  local pool_name="$1"

  # Check if the pool already exists using common functions
  if ! zfs_pool_exists "$pool_name"; then
    echo "Pool $pool_name does not exist. Please specify an existing pool." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "Using ZFS pool: $pool_name" >> "$LOGFILE"
}

# Create ZFS datasets using common functions
create_zfs_datasets() {
  local pool_name="$1"
  local dataset_list="$2"

  # Convert comma-separated list to array
  IFS=',' read -r -a datasets <<< "$dataset_list"

  for dataset in "${datasets[@]}"; do
    # Check if the dataset already exists using common function
    if zfs_dataset_exists "$pool_name/$dataset"; then
      echo "Dataset $pool_name/$dataset already exists, skipping creation." | tee -a "$LOGFILE"
      continue
    fi

    # Create the ZFS dataset with mountpoint using common functions
    retry_command "zfs create -o mountpoint=/mnt/pve/$dataset $pool_name/$dataset"
    echo "[$(date)] Created ZFS dataset: $pool_name/$dataset" >> "$LOGFILE"
  done
}

# Main execution using common functions
main() {
  check_root
  install_zfs_packages

  # Ensure pool name and dataset list are specified using common function
  if [[ -z "$POOL_NAME" || -z "$DATASET_LIST" ]]; then
    echo "Error: Pool name (-p) and dataset list (-d) must be specified." | tee -a "$LOGFILE"
    exit 1
  fi

  check_or_create_pool "$POOL_NAME"
  create_zfs_datasets "$POOL_NAME" "$DATASET_LIST"
}

main