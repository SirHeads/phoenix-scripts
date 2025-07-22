#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.0.8
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh [-q "quickos_dataset_list"] [-f "fastdata_dataset_list"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Unset LOGFILE to avoid readonly conflicts
unset LOGFILE 2>/dev/null || true

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
while getopts ":q:f:" opt; do
  case ${opt} in
    q )
      QUICKOS_DATASET_LIST=($OPTARG)
      ;;
    f )
      FASTDATA_DATASET_LIST=($OPTARG)
      ;;
    \? )
      echo "Invalid option: $OPTARG" | tee -a "$LOGFILE"
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Ensure script runs as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check for pvesm availability
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "Error: pvesm command not found. Ensure this script is running on a Proxmox VE system." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Verified pvesm availability" >> "$LOGFILE"
}

# Initialize logging
setup_logging

# Create datasets for quickOS pool
create_quickos_datasets() {
  local pool="$QUICKOS_POOL"
  local datasets=("${QUICKOS_DATASET_LIST[@]}")

  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"
      local properties
      IFS=',' read -r -a properties <<< "${QUICKOS_DATASET_PROPERTIES[$dataset]}"
      local zfs_properties=()
      for prop in "${properties[@]}"; do
        zfs_properties+=("-o $prop")
      done

      if ! zfs_dataset_exists "$pool/$dataset"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" "${zfs_properties[@]}"
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        set_zfs_properties "$pool/$dataset" "${zfs_properties[@]/-o /}"
        echo "[$(date)] Updated properties for ZFS dataset: $pool/$dataset" >> "$LOGFILE"
      fi
    done
  else
    echo "Error: Pool $pool does not exist." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create datasets for fastData pool
create_fastdata_datasets() {
  local pool="$FASTDATA_POOL"
  local datasets=("${FASTDATA_DATASET_LIST[@]}")

  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"
      local properties
      IFS=',' read -r -a properties <<< "${FASTDATA_DATASET_PROPERTIES[$dataset]}"
      local zfs_properties=()
      for prop in "${properties[@]}"; do
        zfs_properties+=("-o $prop")
      done

      if ! zfs_dataset_exists "$pool/$dataset"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" "${zfs_properties[@]}"
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        set_zfs_properties "$pool/$dataset" "${zfs_properties[@]/-o /}"
        echo "[$(date)] Updated properties for ZFS dataset: $pool/$dataset" >> "$LOGFILE"
      fi
    done
  else
    echo "Error: Pool $pool does not exist." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Add datasets as Proxmox storage
add_proxmox_storage() {
  check_pvesm

  # Add quickOS/vm-disks and quickOS/lxc-disks as ZFS storage
  for dataset in "vm-disks" "lxc-disks"; do
    local storage_id="zfs-$(echo "$dataset" | tr '/' '-')"
    if ! pvesm status | grep -q "^$storage_id"; then
      retry_command "pvesm add zfspool $storage_id -pool $QUICKOS_POOL/$dataset -content images"
      echo "[$(date)] Added Proxmox ZFS storage: $storage_id for $QUICKOS_POOL/$dataset" >> "$LOGFILE"
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
    fi
  done
}

# Main execution
main() {
  check_root
  setup_logging
  create_quickos_datasets
  create_fastdata_datasets
  add_proxmox_storage

  echo "[$(date)] Completed ZFS dataset setup" >> "$LOGFILE"
}

main