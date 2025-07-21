#!/bin/bash

# common.sh
# Shared functions for Proxmox VE setup scripts
# Version: 1.2.2
# Author: Heads, Grok, Devstral
# Usage: Source this script in other setup scripts to use common functions
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Constants
LOGFILE="/var/log/proxmox_setup.log"
readonly LOGFILE
LOGDIR=$(dirname "$LOGFILE")

# Ensure log directory exists and is writable
setup_logging() {
  mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR"; exit 1; }
  touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE"; exit 1; }
  chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE"; exit 1; }
  echo "[$(date)] Initialized logging for $(basename "$0")" >> "$LOGFILE"
}

# Check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create ZFS dataset with properties and mount point
create_zfs_dataset() {
  local pool="$1"
  local dataset="$2"
  local mountpoint="$3"
  shift 3
  local properties=("$@")

  if zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    echo "Dataset $pool/$dataset already exists, skipping creation" | tee -a "$LOGFILE"
    return 0
  fi

  # Create the dataset with mount point and properties
  zfs create -o mountpoint=$mountpoint "${properties[@]}" "$pool/$dataset" || {
    echo "Error: Failed to create ZFS dataset $pool/$dataset with mountpoint $mountpoint" | tee -a "$LOGFILE"
    exit 1
  }

  # Verify the dataset was created successfully
  if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    echo "Error: Failed to verify ZFS dataset creation for $pool/$dataset" | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Successfully created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
}

# Set ZFS properties
set_zfs_properties() {
  local dataset="$1"
  shift
  local properties=("$@")

  for prop in "${properties[@]}"; do
    zfs set "$prop" "$dataset" || {
      echo "Error: Failed to set property $prop on $dataset" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Set property $prop on $dataset" >> "$LOGFILE"
  done
}

# Configure NFS export
configure_nfs_export() {
  local dataset="$1"
  local mountpoint="$2"
  local subnet="$3"
  local options="$4"

  echo "$mountpoint $subnet($options)" >> /etc/exports || {
    echo "Error: Failed to add NFS export for $mountpoint" | tee -a "$LOGFILE"
    exit 1
  }

  exportfs -ra || {
    echo "Error: Failed to refresh NFS exports" | tee -a "$LOGFILE"
    exit 1
  }

  echo "[$(date)] Configured NFS export for $dataset at $mountpoint" >> "$LOGFILE"
}

# Retry a command multiple times
retry_command() {
  local cmd="$@"
  local max_attempts=3
  local attempt=0

  until $cmd; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Command failed, retrying ($((attempt + 1))/${max_attempts}): $cmd" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Error: Command failed after ${max_attempts} attempts: $cmd" | tee -a "$LOGFILE"
      exit 1
    fi
  done
}

# Add user to a group
add_user_to_group() {
  local username="$1"
  local group="$2"

  if ! id -nG "$username" | grep -qw "$group"; then
    usermod -aG "$group" "$username" || {
      echo "Error: Failed to add user $username to group $group" | tee -a "$LOGFILE"
      exit 1
    }
  fi
}

# Verify NFS exports
verify_nfs_exports() {
  if ! exportfs -v >/dev/null 2>&1; then
    echo "Error: Failed to verify NFS exports" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] NFS exports verified" >> "$LOGFILE"
}

# Check if a ZFS pool exists using common functions
zfs_pool_exists() {
  local pool="$1"
  if zpool list -H -o name | grep -q "^$pool$"; then
    return 0
  fi
  return 1
}

# Check if a ZFS dataset exists using zfs list -H -o name
zfs_dataset_exists() {
  local dataset="$1"
  if zfs list -H -o name | grep -q "^$dataset$"; then
    return 0
  fi
  return 1
}

# Initialize logging
setup_logging