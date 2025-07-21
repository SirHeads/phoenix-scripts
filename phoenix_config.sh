#!/bin/bash

# phoenix_config.sh
# Configuration variables for Proxmox VE setup scripts
# Version: 1.0.6
# Author: Heads, Grok, Devstral

# Define log file location (also defined in common.sh)
LOGFILE="/var/log/proxmox_setup.log"
export LOGFILE

# Load configuration variables from environment or defaults
load_config() {
  # Validate PROXMOX_NFS_SERVER format before exporting
  if [[ -n "$PROXMOX_NFS_SERVER" ]]; then
    if ! [[ "$PROXMOX_NFS_SERVER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "Error: Invalid PROXMOX_NFS_SERVER format: $PROXMOX_NFS_SERVER" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    PROXMOX_NFS_SERVER="192.168.0.2"
  fi

  # Validate DEFAULT_SUBNET format before exporting
  if [[ -n "$DEFAULT_SUBNET" ]]; then
    if ! [[ "$DEFAULT_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "Error: Invalid DEFAULT_SUBNET format: $DEFAULT_SUBNET" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    DEFAULT_SUBNET="192.168.0.0/24"
  fi

  # Define Samba user (default to 'admin')
  SMB_USER=${SMB_USER:-"admin"}
  export SMB_USER

  # Define data and log drives for ZFS pool creation
  DATA_DRIVE=${DATA_DRIVE:-""}
  export DATA_DRIVE
  LOG_DRIVE=${LOG_DRIVE:-""}
  export LOG_DRIVE

  # Define default ZFS pool name (rpool)
  POOL_NAME=${POOL_NAME:-"rpool"}
  export POOL_NAME

  # Define arrays for ZFS and NFS datasets to create for consistency with other scripts
  read -r -a ZFS_DATASET_LIST <<< "shared-prod-data,shared-prod-data-sync"
  export ZFS_DATASET_LIST
  read -r -a NFS_DATASET_LIST <<< "shared-prod-data,shared-prod-data-sync"
  export NFS_DATASET_LIST

  # Define base mount point for datasets
  MOUNT_POINT_BASE="/mnt/pve"
  export MOUNT_POINT_BASE

  echo "[$(date)] Configuration variables loaded" >> "$LOGFILE"
}

# Initialize logging and load configuration variables using common.sh's setup_logging
setup_logging
load_config