#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.0.6
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh [-q "quickos_dataset_list"] [-f "fastdata_dataset_list"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

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

# Create sub-datasets for VMs and LXC containers
create_sub_datasets() {
  local pool="$1"
  local parent_dataset="$2"
  local count="$3"
  local prefix="$4"

  for i in $(seq 1 "$count"); do
    local sub_dataset="${parent_dataset}/${prefix}${i}"
    if ! zfs_dataset_exists "$pool/$sub_dataset"; then
      create_zfs_dataset "$pool" "$sub_dataset" "none" -o compression=lz4 -o atime=off
      echo "[$(date)] Created sub-dataset: $pool/$sub_dataset" >> "$LOGFILE"
    else
      echo "[$(date)] Sub-dataset $pool/$sub_dataset already exists, skipping" >> "$LOGFILE"
    fi
  done
}

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

      # Create sub-datasets for vm-disks and lxc-disks
      if [[ "$dataset" == "vm-disks" ]]; then
        create_sub_datasets "$pool" "$dataset" 10 "vm"  # Create 10 VM sub-datasets
      elif [[ "$dataset" == "lxc-disks" ]]; then
        create_sub_datasets "$pool" "$dataset" 10 "lxc"  # Create 10 LXC sub-datasets
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

  # Add quickOS/shared-prod-data and shared-prod-data-sync as NFS storage
  for dataset in "shared-prod-data" "shared-prod-data-sync"; do
    local storage_id="nfs-$(echo "$dataset" | tr '/' '-')"
    local mountpoint="$MOUNT_POINT_BASE/$dataset"
    if ! pvesm status | grep -q "^$storage_id"; then
      retry_command "pvesm add nfs $storage_id -server $PROXMOX_NFS_SERVER -path $mountpoint -content images"
      echo "[$(date)] Added Proxmox NFS storage: $storage_id for $QUICKOS_POOL/$dataset" >> "$LOGFILE"
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
    fi
  done

  # Add fastData datasets as NFS storage
  for dataset in "${FASTDATA_DATASET_LIST[@]}"; do
    local storage_id="nfs-$(echo "$dataset" | tr '/' '-')"
    local mountpoint="$MOUNT_POINT_BASE/$dataset"
    local content="images"
    if [[ "$dataset" == "shared-backups" ]]; then
      content="backup"
    elif [[ "$dataset" == "shared-iso" ]]; then
      content="iso"
    fi
    if ! pvesm status | grep -q "^$storage_id"; then
      retry_command "pvesm add nfs $storage_id -server $PROXMOX_NFS_SERVER -path $mountpoint -content $content"
      echo "[$(date)] Added Proxmox NFS storage: $storage_id for $FASTDATA_POOL/$dataset" >> "$LOGFILE"
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
    fi
  done
}

# Configure snapshot policy
configure_snapshots() {
  local datasets=("${QUICKOS_DATASET_LIST[@]}" "${FASTDATA_DATASET_LIST[@]}")
  for dataset in "${datasets[@]}"; do
    local pool="$QUICKOS_POOL"
    if [[ "${FASTDATA_DATASET_LIST[*]}" =~ "$dataset" ]]; then
      pool="$FASTDATA_POOL"
    fi
    if zfs_dataset_exists "$pool/$dataset"; then
      zfs set com.sun:auto-snapshot=true "$pool/$dataset" || {
        echo "Warning: Failed to enable auto-snapshot on $pool/$dataset" >> "$LOGFILE"
      }
      echo "[$(date)] Enabled auto-snapshot on $pool/$dataset" >> "$LOGFILE"
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
  configure_snapshots

  echo "[$(date)] Completed ZFS dataset setup" >> "$LOGFILE"
}

main