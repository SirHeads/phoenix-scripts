#!/bin/bash

# phoenix_setup_zfs_pools.sh
# Configures ZFS pools on Proxmox VE
# Version: 1.2.0
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_pools.sh [-q "quickos_drives"] [-f "fastdata_drive"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -q)
      QUICKOS_DRIVES="$2"
      shift 2
      ;;
    -f)
      FASTDATA_DRIVE="$2"
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
  local pool_name="$1"

  # Verify the ZFS pool existence with common function
  if ! zfs_pool_exists "$pool_name"; then
    echo "Error: Pool $pool_name does not exist. Please specify an existing pool." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Using ZFS pool: $pool_name" >> "$LOGFILE"
}

# Verify the drive exists and isn't part of an existing ZFS pool
check_available_drives() {
  local drive="$1"

  # Check if the drive exists
  if ! lsblk -d -o NAME | grep -q "^${drive}$"; then
    echo "Error: Drive $drive does not exist." | tee -a "$LOGFILE"
    exit 1
  fi

  # Log drive type (e.g., NVMe or SATA)
  DRIVE_TYPE=$(lsblk -d -o MODEL,TRAN | grep "^${drive}" | awk '{print $2}')
  if [[ -z "$DRIVE_TYPE" ]]; then
    echo "[$(date)] Drive $drive type could not be determined, proceeding anyway" >> "$LOGFILE"
  else
    echo "[$(date)] Drive $drive is of type $DRIVE_TYPE" >> "$LOGFILE"
  fi

  # Check if the drive is already in use by a ZFS pool
  if zpool status | grep -q "^[[:space:]]*$drive "; then
    echo "Error: Drive $drive is already in use by another ZFS pool." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Verified that drive $drive is available" >> "$LOGFILE"
}

# Check system RAM to ensure it's sufficient for ZFS_ARC_MAX
check_system_ram() {
  local zfs_arc_max="$ZFS_ARC_MAX"
  local required_ram=$((zfs_arc_max * 2)) # Require at least 2x ZFS_ARC_MAX
  local total_ram=$(free -b | awk '/Mem:/ {print $2}')

  if [[ $total_ram -lt $required_ram ]]; then
    echo "Warning: System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($((zfs_arc_max / 1024 / 1024 / 1024)) GB). This may cause memory issues." | tee -a "$LOGFILE"
    read -p "Continue with current ZFS_ARC_MAX setting? (y/n): " RAM_CONFIRMATION
    if [[ "$RAM_CONFIRMATION" != "y" && "$RAM_CONFIRMATION" != "Y" ]]; then
      echo "Error: Aborted due to insufficient RAM for ZFS_ARC_MAX." | tee -a "$LOGFILE"
      exit 1
    fi
  fi
  echo "[$(date)] Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX" >> "$LOGFILE"
}

# Create ZFS pools using common functions (default to QUICKOS_DATASET_LIST and FASTDATA_DATASET_LIST if not specified)
create_zfs_pools() {
  # Create quickOS pool (mirrored)
  if zfs_pool_exists "$QUICKOS_POOL"; then
    echo "Pool $QUICKOS_POOL already exists, skipping creation" | tee -a "$LOGFILE"
  else
    if [[ -z "$QUICKOS_DRIVES" ]] || [[ $(echo "$QUICKOS_DRIVES" | wc -w) -ne 2 ]]; then
      echo "Error: Exactly two drives required for $QUICKOS_POOL (mirrored)" | tee -a "$LOGFILE"
      exit 1
    fi
    for drive in $QUICKOS_DRIVES; do
      check_available_drives "$drive"
    done
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off $QUICKOS_POOL mirror $QUICKOS_DRIVES"
    echo "[$(date)] Created ZFS pool: $QUICKOS_POOL on $QUICKOS_DRIVES" >> "$LOGFILE"
  fi

  # Create fastData pool (single)
  if zfs_pool_exists "$FASTDATA_POOL"; then
    echo "Pool $FASTDATA_POOL already exists, skipping creation" | tee -a "$LOGFILE"
  else
    check_available_drives "$FASTDATA_DRIVE"
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off $FASTDATA_POOL $FASTDATA_DRIVE"
    echo "[$(date)] Created ZFS pool: $FASTDATA_POOL on $FASTDATA_DRIVE" >> "$LOGFILE"
  fi

  # Check system RAM before setting ARC limit
  check_system_ram

  # Set ARC limit
  echo "$ZFS_ARC_MAX" > /sys/module/zfs/parameters/zfs_arc_max || {
    echo "Error: Failed to set zfs_arc_max to $ZFS_ARC_MAX" | tee -a "$LOGFILE"
    exit 1
  }
  echo "[$(date)] Set zfs_arc_max to $ZFS_ARC_MAX bytes" >> "$LOGFILE"
}

# Install ZFS packages
install_zfs_packages() {
  if ! check_package "zfsutils-linux"; then
    retry_command "apt-get update"
    retry_command "apt-get install -y zfsutils-linux"
    echo "[$(date)] Installed zfsutils-linux" >> "$LOGFILE"
  fi
}

# Main execution using common functions
main() {
  check_root
  setup_logging

  if [[ -z "$QUICKOS_DRIVES" ]]; then
    read -p "Enter the drives for quickOS pool (e.g., nvme0n1 nvme1n1): " QUICKOS_DRIVES
  fi

  if [[ -z "$FASTDATA_DRIVE" ]]; then
    read -p "Enter the drive for fastData pool (e.g., nvme2n1): " FASTDATA_DRIVE
  fi

  # Ensure ZFS packages are installed before creating pools
  install_zfs_packages

  create_zfs_pools

  echo "[$(date)] Completed ZFS pool setup" >> "$LOGFILE"
}

main