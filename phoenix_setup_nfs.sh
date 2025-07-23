#!/bin/bash

# phoenix_setup_nfs.sh
# Configures NFS server and exports for Proxmox VE
# Version: 1.0.12
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }

# Parse command-line arguments
NO_REBOOT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-reboot)
      NO_REBOOT=true
      shift
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Install NFS packages
install_nfs_packages() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Installing NFS packages..." >> "$LOGFILE"
  if ! retry_command "apt-get install -y nfs-kernel-server nfs-common ufw"; then
    echo "Error: Failed to install NFS packages" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] NFS packages installed" >> "$LOGFILE"
}

# Get server IP in DEFAULT_SUBNET
get_server_ip() {
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  if ! check_interface_in_subnet "$subnet"; then
    echo "Error: No network interface found in subnet $subnet" | tee -a "$LOGFILE"
    exit 1
  fi
  local ip
  ip=$(ip addr show | grep -E "inet.*$(echo "$subnet" | cut -d'/' -f1)" | awk '{print $2}' | cut -d'/' -f1 | head -1)
  if [[ -z "$ip" ]]; then
    echo "Error: Failed to determine server IP in subnet $subnet" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "$ip"
}

# Configure NFS exports
configure_nfs_exports() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Configuring NFS exports..." >> "$LOGFILE"
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  local exports_file="/etc/exports"

  # Check if quickOS and fastData pools exist
  if ! zpool list quickOS >/dev/null 2>&1; then
    echo "Error: ZFS pool quickOS does not exist. Check phoenix_setup_zfs_pools.sh or create_phoenix.sh for pool creation issues." | tee -a "$LOGFILE"
    exit 1
  fi
  if ! zpool list fastData >/dev/null 2>&1; then
    echo "Error: ZFS pool fastData does not exist. Check phoenix_setup_zfs_pools.sh or create_phoenix.sh for pool creation issues." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Verified ZFS pools quickOS and fastData exist" >> "$LOGFILE"

  # Backup existing exports file
  if [[ -f "$exports_file" ]]; then
    if ! cp "$exports_file" "$exports_file.bak.$(date +%F_%H-%M-%S)"; then
      echo "Error: Failed to backup $exports_file" | tee -a "$LOGFILE"
      exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Backed up $exports_file" >> "$LOGFILE"
  fi

  # Clear existing exports file
  if ! : > "$exports_file"; then
    echo "Error: Failed to clear $exports_file" | tee -a "$LOGFILE"
    exit 1
  fi

  # Configure exports for each dataset
  for dataset in "${NFS_DATASET_LIST[@]}"; do
    local zfs_path="$dataset"
    local mount_path="$MOUNT_POINT_BASE/$(echo "$dataset" | tr '/' '-')"
    local options="${NFS_DATASET_OPTIONS[$dataset]:-rw,sync,no_subtree_check,noatime}"

    # Verify ZFS dataset exists
    if ! zfs list "$zfs_path" >/dev/null 2>&1; then
      echo "Error: ZFS dataset $zfs_path does not exist. Run phoenix_setup_zfs_datasets.sh to create it." | tee -a "$LOGFILE"
      echo "Attempting to list available datasets for debugging:" | tee -a "$LOGFILE"
      zfs list -r "$(dirname "$zfs_path")" 2>&1 | tee -a "$LOGFILE"
      exit 1
    fi

    # Create mount point if it doesn't exist
    if ! mkdir -p "$mount_path"; then
      echo "Error: Failed to create mount point $mount_path" | tee -a "$LOGFILE"
      exit 1
    fi

    # Ensure ZFS dataset is mounted at the correct path
    if ! mount | grep -q "$mount_path"; then
      if ! zfs set mountpoint="$mount_path" "$zfs_path"; then
        echo "Error: Failed to set mountpoint for $zfs_path to $mount_path" | tee -a "$LOGFILE"
        exit 1
      fi
    fi

    # Add export to /etc/exports
    if ! echo "$mount_path $subnet($options)" >> "$exports_file"; then
      echo "Error: Failed to add $mount_path to $exports_file" | tee -a "$LOGFILE"
      exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added NFS export for $zfs_path at $mount_path with options $options" >> "$LOGFILE"
  done

  # Restart NFS service to apply exports
  if ! retry_command "exportfs -ra"; then
    echo "Error: Failed to refresh NFS exports" | tee -a "$LOGFILE"
    exit 1
  fi
  if ! retry_command "systemctl restart nfs-kernel-server"; then
    echo "Error: Failed to restart NFS service" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] NFS exports configured and service restarted" >> "$LOGFILE"
}

# Configure firewall for NFS
configure_nfs_firewall() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Configuring firewall for NFS..." >> "$LOGFILE"
  local subnet="${DEFAULT_SUBNET:-10.0.0.0/24}"
  if ! retry_command "ufw allow from $subnet to any port nfs"; then
    echo "Error: Failed to allow NFS in firewall" | tee -a "$LOGFILE"
    exit 1
  fi
  if ! retry_command "ufw allow 111,2049/tcp"; then
    echo "Error: Failed to allow NFS TCP ports in firewall" | tee -a "$LOGFILE"
    exit 1
  fi
  if ! retry_command "ufw allow 111,2049/udp"; then
    echo "Error: Failed to allow NFS UDP ports in firewall" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Firewall configured for NFS" >> "$LOGFILE"
}

# Add NFS storage to Proxmox
add_nfs_storage() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Adding NFS storage to Proxmox..." >> "$LOGFILE"
  if ! command -v pvesm >/dev/null 2>&1; then
    echo "Error: pvesm command not found. Ensure this script is running on a Proxmox VE system." | tee -a "$LOGFILE"
    exit 1
  fi
  local server_ip
  server_ip=$(get_server_ip)

  for dataset in "${NFS_DATASET_LIST[@]}"; do
    local storage_name="nfs-$(echo "$dataset" | tr '/' '-')"
    local export_path="$MOUNT_POINT_BASE/$(echo "$dataset" | tr '/' '-')"
    local storage_info="${DATASET_STORAGE_TYPES[$dataset]}"
    if [[ -z "$storage_info" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Skipping $dataset for NFS storage (not defined in DATASET_STORAGE_TYPES)" >> "$LOGFILE"
      continue
    fi
    local storage_type=$(echo "$storage_info" | cut -d':' -f1)
    local content_type=$(echo "$storage_info" | cut -d':' -f2)
    if [[ "$storage_type" != "nfs" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Skipping $dataset for NFS storage (defined as $storage_type)" >> "$LOGFILE"
      continue
    fi

    # Verify export is active
    if ! showmount -e "$server_ip" | grep -q "$export_path"; then
      echo "Error: NFS export $export_path not available on $server_ip" | tee -a "$LOGFILE"
      exit 1
    fi

    # Check if storage already exists
    if pvesm status | grep -q "^$storage_name"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Proxmox storage $storage_name already exists, skipping" >> "$LOGFILE"
      continue
    fi

    # Create a dedicated local mount point for the NFS storage
    local local_mount="/mnt/nfs/$storage_name"
    if ! mkdir -p "$local_mount"; then
      echo "Error: Failed to create local mount point $local_mount" | tee -a "$LOGFILE"
      exit 1
    fi

    # Add NFS storage to Proxmox with explicit path
    if ! retry_command "pvesm add nfs $storage_name --server $server_ip --export $export_path --content $content_type --path $local_mount --options vers=4"; then
      echo "Error: Failed to add NFS storage $storage_name" | tee -a "$LOGFILE"
      exit 1
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Added NFS storage $storage_name for $export_path at $local_mount with content $content_type" >> "$LOGFILE"
  done
}

# Main execution
main() {
  setup_logging
  check_root
  install_nfs_packages
  configure_nfs_exports
  configure_nfs_firewall
  add_nfs_storage
  if [[ "$NO_REBOOT" == false ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Forcing reboot to apply NFS changes in 10 seconds. Press Ctrl+C to cancel." | tee -a "$LOGFILE"
    sleep 10
    reboot
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Reboot skipped due to --no-reboot flag. Please reboot manually to apply NFS changes." | tee -a "$LOGFILE"
  fi
}

main
echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Successfully completed NFS setup" >> "$LOGFILE"
exit 0