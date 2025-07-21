#!/bin/bash

# phoenix_config.sh
# Configuration file for Proxmox VE setup scripts
# Version: 1.0.5
# Author: Heads, Grok, Devstral

# Set default values for common variables
DEFAULT_LOGFILE="/var/log/proxmox_setup.log"
LOGFILE=${LOGFILE:-$DEFAULT_LOGFILE}
PROXMOX_NFS_SERVER="192.168.0.2" # Example NFS server IP (modify as needed)
DEFAULT_SUBNET="10.0.0.0/24"    # Default network subnet
SMB_USER="admin"                 # Default Samba username

# ZFS Pool and Dataset Configuration
DATA_DRIVE=${DATA_DRIVE:-""}                     # Data drive for ZFS pool
LOG_DRIVE=${LOG_DRIVE:-""}                       # Log drive for ZFS pool
POOL_NAME=${POOL_NAME:-"rpool"}                  # Primary ZFS pool name
ZFS_DATASET_LIST="shared-prod-data,shared-prod-data-sync,shared-test-data,shared-test-data-sync,backups,iso,bulk-data"
NFS_DATASET_LIST="shared-prod-data,shared-prod-data-sync"

# Common directory paths and mountpoints
LOGFILE=${LOGFILE:-$DEFAULT_LOGFILE}
LOGDIR=$(dirname "$LOGFILE")
MOUNT_POINT_BASE="/mnt/pve"  # Base mount point for ZFS datasets

# Constants for ZFS
ARC_MAX=$((24 * 1024 * 1024 * 1024))  # 24GB ARC cache for a 96GB RAM system (adjust as needed)

# Common functions to be used across setup scripts
setup_logging() {
    mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR"; exit 1; }
    touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
    chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE"; exit 1; }
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
}

# Function to load configuration variables (called at the beginning of each setup script)
load_config() {
    export LOGFILE=${LOGFILE:-$DEFAULT_LOGFILE}
    export PROXMOX_NFS_SERVER=${PROXMOX_NFS_SERVER:-"192.168.0.2"}
    export DEFAULT_SUBNET=${DEFAULT_SUBNET:-"10.0.0.0/24"}
    export SMB_USER=${SMB_USER:-"admin"}
    export DATA_DRIVE=${DATA_DRIVE:-""}
    export LOG_DRIVE=${LOG_DRIVE:-""}
    export POOL_NAME=${POOL_NAME:-"rpool"}
    export ZFS_DATASET_LIST=${ZFS_DATASET_LIST:-"shared-prod-data,shared-prod-data-sync,shared-test-data,shared-test-data-sync,backups,iso,bulk-data"}
    export NFS_DATASET_LIST=${NFS_DATASET_LIST:-"shared-prod-data,shared-prod-data-sync"}
}

# Usage:
# source /usr/local/bin/phoenix_config.sh