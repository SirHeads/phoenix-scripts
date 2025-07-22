#!/bin/bash

# phoenix_config.sh
# Configuration variables for Proxmox VE setup scripts
# Version: 1.2.2
# Author: Heads, Grok, Devstral

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }

# Define log file location
# grok said comment out:LOGFILE="/var/log/proxmox_setup.log"
# grok said comment out:export LOGFILE

# Load configuration variables from environment or defaults
load_config() {
  # Validate PROXMOX_NFS_SERVER format
  if [[ -n "$PROXMOX_NFS_SERVER" ]]; then
    if ! [[ "$PROXMOX_NFS_SERVER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "Error: Invalid PROXMOX_NFS_SERVER format: $PROXMOX_NFS_SERVER" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    PROXMOX_NFS_SERVER="10.0.0.13"
  fi

  # Validate DEFAULT_SUBNET format
  if [[ -n "$DEFAULT_SUBNET" ]]; then
    if ! [[ "$DEFAULT_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "Error: Invalid DEFAULT_SUBNET format: $DEFAULT_SUBNET" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    DEFAULT_SUBNET="10.0.0.0/24"
  fi

  # Define Samba user
  SMB_USER=${SMB_USER:-"heads"}
  export SMB_USER

  # Define ZFS pools and drives
  QUICKOS_POOL="quickOS"
  FASTDATA_POOL="fastData"
  export QUICKOS_POOL FASTDATA_POOL
  QUICKOS_DRIVES=${QUICKOS_DRIVES:-""}  # Expect two NVMe drives, e.g., "nvme0n1 nvme1n1"
  FASTDATA_DRIVE=${FASTDATA_DRIVE:-""}  # Single NVMe drive, e.g., "nvme2n1"
  export QUICKOS_DRIVES FASTDATA_DRIVE

  # Define ZFS dataset lists with properties
  declare -A QUICKOS_DATASET_PROPERTIES
  QUICKOS_DATASET_PROPERTIES=(
    ["vm-disks"]="recordsize=128K,compression=lz4,sync=standard,quota=800G"
    ["lxc-disks"]="recordsize=16K,compression=lz4,sync=standard,quota=600G"
    ["shared-prod-data"]="recordsize=128K,compression=lz4,sync=standard,quota=400G"
    ["shared-prod-data-sync"]="recordsize=16K,compression=lz4,sync=always,quota=100G"
  )
  QUICKOS_DATASET_LIST=("vm-disks" "lxc-disks" "shared-prod-data" "shared-prod-data-sync")
  export QUICKOS_DATASET_LIST

  declare -A FASTDATA_DATASET_PROPERTIES
  FASTDATA_DATASET_PROPERTIES=(
    ["shared-test-data"]="recordsize=128K,compression=lz4,sync=standard,quota=500G"
    ["shared-backups"]="recordsize=1M,compression=zstd,sync=standard,quota=2T"
    ["shared-iso"]="recordsize=1M,compression=lz4,sync=standard,quota=100G"
    ["shared-bulk-data"]="recordsize=1M,compression=lz4,sync=standard,quota=1.4T"
    ["shared-test-data-sync"]="recordsize=16K,compression=lz4,sync=always,quota=100G"
  )
  FASTDATA_DATASET_LIST=("shared-test-data" "shared-backups" "shared-iso" "shared-bulk-data" "shared-test-data-sync")
  export FASTDATA_DATASET_LIST

  # Define NFS dataset lists with specific export options
  declare -A NFS_DATASET_OPTIONS
  NFS_DATASET_OPTIONS=(
    ["quickOS/shared-prod-data"]="rw,async,no_subtree_check,noatime"
    ["quickOS/shared-prod-data-sync"]="rw,sync,no_subtree_check,noatime"
    ["fastData/shared-test-data"]="rw,async,no_subtree_check,noatime"
    ["fastData/shared-backups"]="rw,async,no_subtree_check,noatime"
    ["fastData/shared-iso"]="rw,async,no_subtree_check,noatime"
    ["fastData/shared-bulk-data"]="rw,async,no_subtree_check,noatime"
    ["fastData/shared-test-data-sync"]="rw,sync,no_subtree_check,noatime"
  )
  NFS_DATASET_LIST=("quickOS/shared-prod-data" "quickOS/shared-prod-data-sync" "fastData/shared-test-data" "fastData/shared-iso" "fastData/shared-bulk-data" "fastData/shared-backups" "fastData/shared-test-data-sync")
  export NFS_DATASET_LIST

  # Define base mount point for datasets
  MOUNT_POINT_BASE="/mnt/pve"
  export MOUNT_POINT_BASE

  # Define ARC limit (30GB in bytes)
  ZFS_ARC_MAX="32212254720"  # 30GB
  export ZFS_ARC_MAX

  echo "[$(date)] Configuration variables loaded" >> "$LOGFILE"
}

# Initialize logging and load configuration
setup_logging
load_config