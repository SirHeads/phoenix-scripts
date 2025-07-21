#!/bin/bash

# master_setup.sh
# Orchestrates the execution of all Proxmox VE setup scripts
# Version: 1.0.7
# Author: Heads, Grok, Devstral

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }

# Ensure script runs as root using common function
check_root

scripts=(
  "/usr/local/bin/phoenix_proxmox_initial_setup.sh"
  "/usr/local/bin/common.sh"
  "/usr/local/bin/phoenix_config.sh"
  "/usr/local/bin/phoenix_install_nvidia_driver.sh --no-reboot"
  "/usr/local/bin/phoenix_create_admin_user.sh -u adminuser -p 'SecurePass1!'"
  # Check for zfsutils-linux before running ZFS-related scripts
  "if ! dpkg-query -W zfsutils-linux > /dev/null; then apt-get update && apt-get install -y zfsutils-linux; fi"
  "/usr/local/bin/phoenix_setup_zfs_pools.sh -d sdb"
  # Use ZFS_DATASET_LIST from phoenix_config.sh for consistency
  "/usr/local/bin/phoenix_setup_zfs_datasets.sh -p rpool -d $(IFS=','; echo "${ZFS_DATASET_LIST[*]}")"
  "/usr/local/bin/phoenix_setup_nfs.sh --no-reboot"
  "/usr/local/bin/phoenix_setup_samba.sh" # Removed --no-ssl as it's unused
)

# Execute each script in order and exit on failure with detailed error reporting
for script in "${scripts[@]}"; do
  echo "[$(date)] Running: $script" >> "$LOGFILE"
  bash -c "$script" | tee -a "$LOGFILE"
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to execute $script. Exiting." | tee -a "$LOGFILE"
    exit 1
  fi
done

echo "[$(date)] Completed Proxmox VE setup" >> "$LOGFILE"