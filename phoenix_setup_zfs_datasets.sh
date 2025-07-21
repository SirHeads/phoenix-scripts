#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh [-p "pool_name"] [-d "dataset_list"]
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

# Initialize logging for consistent behavior
setup_logging

# Check if pool exists using common functions (default to rpool if not specified)
check_pool() {
  local pool_name="${POOL_NAME:-rpool}"

  # Verify the ZFS pool existence with common function
  if ! zfs_pool_exists "$pool_name"; then
    echo "Error: Pool $pool_name does not exist. Please specify an existing pool." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Using ZFS pool: $pool_name" >> "$LOGFILE"
}

# Create ZFS datasets using common functions (default to ZFS_DATASET_LIST if not specified)
create_zfs_datasets() {
  local pool_name="${POOL_NAME:-rpool}"
  local dataset_list="${DATASET_LIST:-$ZFS_DATASET_LIST}"

  # Ensure the dataset list is provided and not empty
  if [[ -z "$dataset_list" ]]; then
    echo "Error: Dataset list is empty. Please specify datasets via -d or define ZFS_DATASET_LIST in phoenix_config.sh." | tee -a "$LOGFILE"
    exit 1
  fi

  # Parse the comma-separated dataset list and validate each name before creating
  IFS=',' read -r -a datasets <<< "$dataset_list"
  for dataset in "${datasets[@]}"; do
    if [[ ! "$dataset" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
      echo "Error: Invalid dataset name: $dataset (must contain only letters, numbers, hyphens, or underscores)" | tee -a "$LOGFILE"
      exit 1
    fi

    # Ensure the /mnt/pve parent directory exists before creating datasets
    mkdir -p /mnt/pve || { echo "Error: Failed to create /mnt/pve" | tee -a "$LOGFILE"; exit 1; }

    if ! zfs_dataset_exists "$pool_name/$dataset"; then
      # Use the common function for dataset creation with validation and error handling
      create_zfs_dataset "$pool_name" "$dataset" "/mnt/pve/$dataset"
      echo "[$(date)] Created ZFS dataset: $pool_name/$dataset with mountpoint /mnt/pve/$dataset" >> "$LOGFILE"
    else
      echo "Dataset $pool_name/$dataset already exists, skipping creation." | tee -a "$LOGFILE"
    fi
  done
}

# Main execution using common functions
main() {
  check_root
  setup_logging

  # Default pool name to rpool if not specified
  POOL_NAME="${POOL_NAME:-rpool}"

  # Check the existence of the specified pool (or default rpool)
  check_pool "$POOL_NAME"

  # Create ZFS datasets using either user-provided list or default from phoenix_config.sh
  create_zfs_datasets "${POOL_NAME}" "${DATASET_LIST:-$ZFS_DATASET_LIST}"

  echo "[$(date)] Completed ZFS dataset setup" >> "$LOGFILE"
}

main