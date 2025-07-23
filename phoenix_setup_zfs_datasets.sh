#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.2.2
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh [-q "quickos_dataset_list"] [-f "fastdata_dataset_list"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Unset LOGFILE to avoid readonly conflicts
unset LOGFILE 2>/dev/null || true

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }
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

# Ensure script runs only once
STATE_FILE="/var/log/proxmox_setup_state"
if grep -Fx "phoenix_setup_zfs_datasets" "$STATE_FILE" >/dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] phoenix_setup_zfs_datasets already executed, skipping" >> "$LOGFILE"
  exit 0
fi

# Check for pvesm availability
check_pvesm() {
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Error: pvesm command not found" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Verified pvesm availability" >> "$LOGFILE"
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        set_zfs_properties "$pool/$dataset" "${zfs_properties[@]/-o /}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Updated properties for ZFS dataset: $pool/$dataset" >> "$LOGFILE"
      fi
    done
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Error: Pool $pool does not exist" | tee -a "$LOGFILE"
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        set_zfs_properties "$pool/$dataset" "${zfs_properties[@]/-o /}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Updated properties for ZFS dataset: $pool/$dataset" >> "$LOGFILE"
      fi
    done
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Error: Pool $pool does not exist" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Add Proxmox storage
add_proxmox_storage() {
  check_pvesm

  # Process quickOS datasets
  for dataset in "${QUICKOS_DATASET_LIST[@]}"; do
    local full_dataset="quickOS/$dataset"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Processing dataset $full_dataset" >> "$LOGFILE"
    local storage_info="${DATASET_STORAGE_TYPES[$full_dataset]}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_info='$storage_info' for $full_dataset" >> "$LOGFILE"
    
    # Check if storage_info is empty or invalid
    if [[ -z "$storage_info" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: No storage info defined for $full_dataset, skipping" >> "$LOGFILE"
      continue
    fi
    if ! echo "$storage_info" | grep -q ":"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Invalid storage_info format for $full_dataset: '$storage_info', skipping" >> "$LOGFILE"
      continue
    fi

    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_type='$storage_type', content_type='$content_type' for $full_dataset" >> "$LOGFILE"

    # Validate storage_type and content_type
    if [[ -z "$storage_type" || -z "$content_type" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Invalid storage_type or content_type for $full_dataset, skipping" >> "$LOGFILE"
      continue
    fi

    local storage_id="zfs-$(echo "$dataset" | tr '/' '-')"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_id='$storage_id' for $full_dataset" >> "$LOGFILE"

    if ! pvesm status | grep -q "^$storage_id"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Adding storage $storage_id" >> "$LOGFILE"
      if [[ "$storage_type" == "dir" ]]; then
        local mountpoint="$MOUNT_POINT_BASE/$dataset"
        if ! mountpoint -q "$mountpoint"; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Setting mountpoint $mountpoint for $QUICKOS_POOL/$dataset" >> "$LOGFILE"
          zfs set mountpoint="$mountpoint" "$QUICKOS_POOL/$dataset" || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to set mountpoint $mountpoint for $QUICKOS_POOL/$dataset" >> "$LOGFILE"
            exit 1
          }
          zfs mount "$QUICKOS_POOL/$dataset" || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to mount $QUICKOS_POOL/$dataset" >> "$LOGFILE"
            exit 1
          }
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Running pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" >> "$LOGFILE"
        retry_command "pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" || {
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to add $storage_type storage $storage_id" >> "$LOGFILE"
          exit 1
        }
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added Proxmox $storage_type storage: $storage_id for $mountpoint with content $content_type" >> "$LOGFILE"
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Running pvesm add $storage_type $storage_id -pool $QUICKOS_POOL/$dataset -content $content_type" >> "$LOGFILE"
        retry_command "pvesm add $storage_type $storage_id -pool $QUICKOS_POOL/$dataset -content $content_type" || {
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to add $storage_type storage $storage_id" >> "$LOGFILE"
          exit 1
        }
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added Proxmox $storage_type storage: $storage_id for $QUICKOS_POOL/$dataset with content $content_type" >> "$LOGFILE"
      fi
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
    fi
  done

  # Process fastData datasets
  for dataset in "${FASTDATA_DATASET_LIST[@]}"; do
    local full_dataset="fastData/$dataset"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Processing dataset $full_dataset" >> "$LOGFILE"
    local storage_info="${DATASET_STORAGE_TYPES[$full_dataset]}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_info='$storage_info' for $full_dataset" >> "$LOGFILE"
    
    if [[ -z "$storage_info" ]]; then
      echo "[$(,date '+%Y-%m-%d %H:%M:%S %Z')] Skipping $full_dataset for Proxmox storage (likely handled by NFS)" >> "$LOGFILE"
      continue
    fi
    if ! echo "$storage_info" | grep -q ":"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Invalid storage_info format for $full_dataset: '$storage_info', skipping" >> "$LOGFILE"
      continue
    fi

    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_type='$storage_type', content_type='$content_type' for $full_dataset" >> "$LOGFILE"

    local storage_id="zfs-$(echo "$dataset" | tr '/' '-')"
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: storage_id='$storage_id' for $full_dataset" >> "$LOGFILE"

    if ! pvesm status | grep -q "^$storage_id"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Adding storage $storage_id" >> "$LOGFILE"
      if [[ "$storage_type" == "dir" ]]; then
        local mountpoint="$MOUNT_POINT_BASE/$dataset"
        if ! mountpoint -q "$mountpoint"; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Setting mountpoint $mountpoint for $FASTDATA_POOL/$dataset" >> "$LOGFILE"
          zfs set mountpoint="$mountpoint" "$FASTDATA_POOL/$dataset" || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to set mountpoint $mountpoint for $FASTDATA_POOL/$dataset" >> "$LOGFILE"
            exit 1
          }
          zfs mount "$FASTDATA_POOL/$dataset" || {
            echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to mount $FASTDATA_POOL/$dataset" >> "$LOGFILE"
            exit 1
          }
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Running pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" >> "$LOGFILE"
        retry_command "pvesm add $storage_type $storage_id -path $mountpoint -content $content_type" || {
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to add $storage_type storage $storage_id" >> "$LOGFILE"
          exit 1
        }
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added Proxmox $storage_type storage: $storage_id for $mountpoint with content $content_type" >> "$LOGFILE"
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] DEBUG: Running pvesm add $storage_type $storage_id -pool $FASTDATA_POOL/$dataset -content $content_type" >> "$LOGFILE"
        retry_command "pvesm add $storage_type $storage_id -pool $FASTDATA_POOL/$dataset -content $content_type" || {
          echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] ERROR: Failed to add $storage_type storage $storage_id" >> "$LOGFILE"
          exit 1
        }
        echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added Proxmox $storage_type storage: $storage_id for $FASTDATA_POOL/$dataset with content $content_type" >> "$LOGFILE"
      fi
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
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
  echo "phoenix_setup_zfs_datasets" >> "$STATE_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Completed ZFS dataset setup" >> "$LOGFILE"
}

main