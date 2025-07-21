#!/bin/bash

# master_setup.sh
# Orchestrates all Proxmox VE setup scripts
# Version: 1.0.6
# Author: Heads, Grok, Devstral

source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

check_root

# Initialize logging
setup_logging()

scripts=(
    "/path/to/phoenix_proxmox_initial_setup.sh"
    "/path/to/phoenix_install_nvidia_driver.sh --no-reboot"
    "/path/to/phoenix_create_admin_user.sh -u adminuser -p password123"
    "/path/to/phoenix_setup_nfs.sh"
    "/path/to/phoenix_setup_samba.sh"
    "/path/to/phoenix_setup_zfs_pools.sh"
    "/path/to/phoenix_setup_zfs_datasets.sh -p rpool -d 'shared-prod-data,shared-prod-data-sync'"
)

for script in "${scripts[@]}"; do
  echo "[$(date)] Starting $script" >> "$LOGFILE"
  bash "$script" || { echo "Error: Script $script failed." >> "$LOGFILE"; exit 1; }
done

echo "[$(date)] All scripts executed successfully." >> "$LOGFILE"
