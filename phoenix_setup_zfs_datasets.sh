#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets on Proxmox VE
# Version: 1.0.4
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

# Ensure script runs as root using common function
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

# Initialize logging for consistent behavior
setup_logging

# Create datasets for quickOS pool using common functions
create_quickos_datasets() {
  local pool="$QUICKOS_POOL"
  local datasets=("${QUICKOS_DATASET_LIST[@]}")

  # Create datasets only if the pool exists
  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"

      # Create ZFS dataset if it doesn't exist
      if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" -o compression=lz4 -o atime=off
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        echo "[$(date)] ZFS dataset $pool/$dataset already exists, skipping creation" >> "$LOGFILE"
      fi
    done
  else
    echo "Error: Pool $pool does not exist." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Create datasets for fastData pool using common functions
create_fastdata_datasets() {
  local pool="$FASTDATA_POOL"
  local datasets=("${FASTDATA_DATASET_LIST[@]}")

  # Create datasets only if the pool exists
  if zfs_pool_exists "$pool"; then
    for dataset in "${datasets[@]}"; do
      local mountpoint="$MOUNT_POINT_BASE/$dataset"

      # Create ZFS dataset if it doesn't exist
      if ! zfs list -H -o name | grep -q "^$pool/$dataset$"; then
        create_zfs_dataset "$pool" "$dataset" "$mountpoint" -o compression=lz4 -o atime=off
        echo "[$(date)] Created ZFS dataset: $pool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
      else
        echo "[$(date)] ZFS dataset $pool/$dataset already exists, skipping creation" >> "$LOGFILE"
      fi
    done
  else
    echo "Error: Pool $pool does not exist." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Add datasets as Proxmox storage using common functions
add_proxmox_storage() {
  local pool="$1"
  shift
  local datasets=("$@")

  # Check pvesm availability
  check_pvesm

  for dataset in "${datasets[@]}"; do
    local storage_id=$(echo "$dataset" | tr '/' '-')
    if ! pvesm status | grep -q "^$storage_id"; then
      retry_command "pvesm add zfspool $storage_id -pool $pool/$dataset -content images"
      echo "[$(date)] Added Proxmox storage: $storage_id for $pool/$dataset" >> "$LOGFILE"
    else
      echo "[$(date)] Proxmox storage $storage_id already exists, skipping" >> "$LOGFILE"
    fi
  done
}

# Main execution using common functions
main() {
  check_root
  setup_logging

  # Use environment variables or command-line arguments if set, otherwise fall back to config
  if [[ -z "${QUICKOS_DATASET_LIST+x}" && -z "${OPTARG+x}" ]]; then
    echo "[$(date)] Using QUICKOS_DATASET_LIST from phoenix_config.sh" >> "$LOGFILE"
  else
    echo "[$(date)] Using provided QUICKOS_DATASET_LIST: ${QUICKOS_DATASET_LIST[*]}" >> "$LOGFILE"
  fi

  if [[ -z "${FASTDATA_DATASET_LIST+x}" && -z "${OPTARG+x}" ]]; then
    echo "[$(date)] Using FASTDATA_DATASET_LIST from phoenix_config.sh" >> "$LOGFILE"
  else
    echo "[$(date)] Using provided FASTDATA_DATASET_LIST: ${FASTDATA_DATASET_LIST[*]}" >> "$LOGFILE"
  fi

  create_quickos_datasets
  create_fastdata_datasets
  add_proxmox_storage "$QUICKOS_POOL" "${QUICKOS_DATASET_LIST[@]}"
  add_proxmox_storage "$FASTDATA_POOL" "${FASTDATA_DATASET_LIST[@]}"

  echo "[$(date)] Completed ZFS dataset setup" >> "$LOGFILE"
}

main