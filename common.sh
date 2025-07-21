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

# Initialize logging
setup_logging

# Check network connectivity to a server
check_network_connectivity() {
  local server="$1"
  ping -c 1 "$server" >/dev/null 2>&1 || { echo "Error: Cannot reach $server" | tee -a "$LOGFILE"; exit 1; }
  echo "[$(date)] Network connectivity to $server verified" >> "$LOGFILE"
}

# Check if an interface has an IP in the specified subnet
check_interface_in_subnet() {
  local subnet="$1"
  ip addr | grep -q "$subnet" || { echo "Error: No interface in subnet $subnet" | tee -a "$LOGFILE"; exit 1; }
  echo "[$(date)] Interface in subnet $subnet verified" >> "$LOGFILE"
}

# Check internet connectivity
check_internet_connectivity() {
  ping -c 1 8.8.8.8 >/dev/null 2>&1 || { echo "Warning: No internet connectivity" | tee -a "$LOGFILE"; }
  echo "[$(date)] Internet connectivity check completed" >> "$LOGFILE"
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
  if ! exportfs -v; then
    echo "Error: Failed to verify NFS exports" | tee -a "$LOGFILE"
    exit 1
  fi

  # Additional verification logic can be added here as needed
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

# Create ZFS dataset with mount point validation and error handling
create_zfs_dataset() {
  local pool="$1"
  local dataset="$2"
  local mountpoint="$3"

  if zfs list -H -o name | grep -q "^$pool/$dataset$"; then
    echo "Dataset $pool/$dataset already exists, skipping creation" | tee -a "$LOGFILE"
    return 0
  fi

  # Create the dataset with mount point
  zfs create -o mountpoint=$mountpoint "$pool/$dataset" || {
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

# Retry a command multiple times before giving up (common function for robustness)
retry_command() {
  local cmd="$@"
  local max_attempts=3
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    echo "[$(date)] Attempting: $cmd" >> "$LOGFILE"
    eval "$cmd"
    if [[ $? -eq 0 ]]; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  echo "Error: Command failed after $max_attempts attempts: $cmd" | tee -a "$LOGFILE"
  exit 1
}

# Check if a package is installed (common function for package management)
check_package() {
  local pkg="$1"

  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep "install ok installed" >/dev/null
}