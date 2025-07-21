#!/bin/bash

# phoenix_config.sh
# Configuration variables for Proxmox VE setup scripts
# Version: 1.2.0
# Author: Heads, Grok, Devstral

# Define log file location
LOGFILE="/var/log/proxmox_setup.log"
export LOGFILE

# Load configuration variables from environment or defaults
load_config() {
  # Validate PROXMOX_NFS_SERVER format
  if [[ -n "$PROXMOX_NFS_SERVER" ]]; then
    if ! [[ "$PROXMOX_NFS_SERVER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "Error: Invalid PROXMOX_NFS_SERVER format: $PROXMOX_NFS_SERVER" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    PROXMOX_NFS_SERVER="192.168.0.2"
  fi

  # Validate DEFAULT_SUBNET format
  if [[ -n "$DEFAULT_SUBNET" ]]; then
    if ! [[ "$DEFAULT_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "Error: Invalid DEFAULT_SUBNET format: $DEFAULT_SUBNET" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    DEFAULT_SUBNET="192.168.0.0/24"
  fi

  # Define Samba user
  SMB_USER=${SMB_USER:-"admin"}
  export SMB_USER

  # Define ZFS pools and drives
  QUICKOS_POOL="quickOS"
  FASTDATA_POOL="fastData"
  export QUICKOS_POOL FASTDATA_POOL
  QUICKOS_DRIVES=${QUICKOS_DRIVES:-""}  # Expect two NVMe drives, e.g., "nvme0n1 nvme1n1"
  FASTDATA_DRIVE=${FASTDATA_DRIVE:-""}  # Single NVMe drive, e.g., "nvme2n1"
  export QUICKOS_DRIVES FASTDATA_DRIVE

  # Define ZFS dataset lists
  QUICKOS_DATASET_LIST=("vm-disks" "lxc-disks" "shared-prod-data" "shared-prod-data-sync" "shared-backups")
  FASTDATA_DATASET_LIST=("shared-test-data" "shared-iso" "shared-bulk-data")
  export QUICKOS_DATASET_LIST FASTDATA_DATASET_LIST

  # Define NFS dataset lists
  NFS_DATASET_LIST=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "fastData/shared-test-data" "fastData/shared-bulk-data")
  export NFS_DATASET_LIST

  # Define base mount point for datasets
  MOUNT_POINT_BASE="/mnt/pve"
  export MOUNT_POINT_BASE

  # Define ARC limit (30GB in bytes)
  ZFS_ARC_MAX="32212254720"
  export ZFS_ARC_MAX

  echo "[$(date)] Configuration variables loaded" >> "$LOGFILE"
}

# Initialize logging and load configuration
setup_logging
load_config