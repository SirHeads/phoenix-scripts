#!/bin/bash

# common.sh
# Shared functions for Proxmox VE setup scripts
# Version: 1.2.6
# Author: Heads, Grok, Devstral
# Usage: Source this script in other setup scripts to use common functions
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Constants
LOGFILE="/var/log/proxmox_setup.log"
LOGDIR=$(dirname "$LOGFILE")

# Ensure log directory exists and is writable
setup_logging() {
  mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR" | tee -a /dev/stderr; exit 1; }
  touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE" | tee -a /dev/stderr; exit 1; }
  chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE" | tee -a /dev/stderr; exit 1; }
  echo "[$(date)] Initialized logging for $(basename "$0")" >> "$LOGFILE"
}

# Check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check if a package is installed
check_package() {
  local package="$1"
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

# Check network connectivity to a specific host
check_network_connectivity() {
  local host="$1"
  local max_attempts=3
  local attempt=0
  local timeout=5

  if [[ -z "$host" ]]; then
    echo "Error: No host provided for connectivity check." | tee -a "$LOGFILE"
    exit 1
  fi

  until ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Failed to reach $host, retrying ($((attempt + 1))/$max_attempts)" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Error: Cannot reach $host after $max_attempts attempts. Check network configuration." | tee -a "$LOGFILE"
      exit 1
    fi
  done
  echo "[$(date)] Network connectivity to $host verified" >> "$LOGFILE"
}

# Check internet connectivity
check_internet_connectivity() {
  local dns_server="8.8.8.8"
  local max_attempts=3
  local attempt=0
  local timeout=5

  until ping -c 1 -W "$timeout" "$dns_server" >/dev/null 2>&1; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Failed to reach $dns_server, retrying ($((attempt + 1))/$max_attempts)" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Warning: No internet connectivity to $dns_server after $max_attempts attempts. Some operations may fail." | tee -a "$LOGFILE"
      return 1
    fi
  done
  echo "[$(date)] Internet connectivity to $dns_server verified" >> "$LOGFILE"
}

check_interface_in_subnet() {
  local subnet="$1"
  local found=0

  if ! [[ "$subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "Error: Invalid subnet format: $subnet" | tee -a "$LOGFILE"
    exit 1
  fi

  local subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\./')
  while IFS= read -r line; do
    if [[ "$line" =~ inet\ (10\.0\.0\.[0-9]+/[0-9]+) ]]; then
      ip_with_mask="${BASH_REMATCH[1]}"
      ip=$(echo "$ip_with_mask" | cut -d'/' -f1)
      if [[ "$ip" =~ ^$subnet_prefix ]]; then
        found=1
        echo "[$(date)] Found network interface with IP $ip_with_mask in subnet $subnet" >> "$LOGFILE"
        break
      fi
    fi
  done < <(ip addr show | grep inet)

  if [[ $found -eq 0 ]]; then
    echo "Warning: No network interface found in subnet $subnet. NFS may not function correctly." | tee -a "$LOGFILE"
    return 1
  fi
  return 0
}

  # Extract IP addresses from all interfaces
{  
  while IFS= read -r line; do
    if [[ "$line" =~ inet\ ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}) ]]; then
      ip_with_mask="${BASH_REMATCH[1]}"
      ip=$(echo "$ip_with_mask" | cut -d'/' -f1)
      # Use ipcalc if available for precise subnet matching
      if command -v ipcalc >/dev/null 2>&1; then
        if ipcalc -cs "$ip_with_mask" "$subnet"; then
          found=1
          echo "[$(date)] Found network interface with IP $ip_with_mask in subnet $subnet" >> "$LOGFILE"
          break
        fi
      else
        # Fallback to basic subnet matching
        subnet_prefix=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\./')
        if [[ "$ip" =~ ^$subnet_prefix ]]; then
          found=1
          echo "[$(date)] Found network interface with IP $ip_with_mask in subnet $subnet (basic match)" >> "$LOGFILE"
          break
        fi
      fi
    fi
  done < <(ip addr show | grep inet)

  if [[ $found -eq 0 ]]; then
    echo "Warning: No network interface found in subnet $subnet. NFS may not function correctly." | tee -a "$LOGFILE"
    return 1
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
  zfs create -o mountpoint="$mountpoint" "${properties[@]}" "$pool/$dataset" || {
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
  local cmd="$1"
  local max_attempts=3
  local attempt=0

  until bash -c "$cmd"; do
    if ((attempt < max_attempts)); then
      echo "[$(date)] Command failed, retrying ($((attempt + 1))/${max_attempts}): $cmd" >> "$LOGFILE"
      ((attempt++))
      sleep 5
    else
      echo "Error: Command failed after ${max_attempts} attempts: $cmd" | tee -a "$LOGFILE"
      return 1
    fi
  done
  echo "[$(date)] Command succeeded: $cmd" >> "$LOGFILE"
  return 0
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
  echo "[$(date)] Added user $username to group $group" >> "$LOGFILE"
}

# Verify NFS exports
verify_nfs_exports() {
  if ! exportfs -v >/dev/null 2>&1; then
    echo "Error: Failed to verify NFS exports" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] NFS exports verified" >> "$LOGFILE"
}

# Check if a ZFS pool exists
zfs_pool_exists() {
  local pool="$1"
  if zpool list -H -o name | grep -q "^$pool$"; then
    return 0
  fi
  return 1
}

# Check if a ZFS dataset exists
zfs_dataset_exists() {
  local dataset="$1"
  if zfs list -H -o name | grep -q "^$dataset$"; then
    return 0
  fi
  return 1
}

# Initialize logging
setup_logging