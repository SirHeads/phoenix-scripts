#!/bin/bash

# phoenix_setup_nfs.sh
# Installs and configures NFS server on Proxmox VE
# Version: 1.0.5
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh [-o "nfs_export_options"]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
NFS_EXPORT_OPTIONS="rw,sync,no_subtree_check"
while getopts ":o:" opt; do
  case ${opt} in
    o )
      NFS_EXPORT_OPTIONS=$OPTARG
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
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
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

# Initialize logging using the configuration setup_logging function
setup_logging

# Prompt for network subnet using common functions
prompt_for_subnet() {
    read -p "Enter network subnet for NFS (default: ${DEFAULT_SUBNET}): " NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET" | tee -a "$LOGFILE"
        exit 1
    fi
}

# Check network connectivity using common functions
check_network() {
    echo "Checking network connectivity..." | tee -a "$LOGFILE"

    # Check localhost resolution
    if ! ping -c 1 localhost >/dev/null 2>&1; then
        echo "Warning: Hostname 'localhost' does not resolve to 127.0.0.1. Check /etc/hosts." | tee -a "$LOGFILE"
    fi

    # Use IP_ADDRESS from phoenix_proxmox_initial_setup.sh if set
    if [[ -n "$IP_ADDRESS" ]]; then
        PROXMOX_NFS_SERVER="$IP_ADDRESS"
        export PROXMOX_NFS_SERVER
    fi

    # Check network connectivity for PROXMOX_NFS_SERVER using common function
    check_network_connectivity "$PROXMOX_NFS_SERVER"

    # Check if an interface has an IP in NFS_SUBNET using common functions
    check_interface_in_subnet "$NFS_SUBNET"

    # Check internet connectivity using common functions
    check_internet_connectivity
}

# Install required NFS packages using common functions
install_prerequisites() {
    if ! check_package nfs-kernel-server; then
        retry_command "apt-get update && apt-get install -y nfs-kernel-server nfs-common ufw"
        echo "[$(date)] Installed NFS prerequisites" >> "$LOGFILE"
    fi

    if ! systemctl is-active --quiet nfs-kernel-server; then
        retry_command "systemctl start nfs-kernel-server"
        retry_command "systemctl enable nfs-kernel-server"
        echo "[$(date)] Started and enabled nfs-kernel-server" >> "$LOGFILE"
    fi
}

# Configure NFS server
configure_nfs() {
    echo "Configuring NFS exports..." | tee -a "$LOGFILE"

    # Ensure the base mount directory exists
    mkdir -p /mnt/pve || { echo "Error: Failed to create /mnt/pve" | tee -a "$LOGFILE"; exit 1; }

    for dataset in "${NFS_DATASET_LIST[@]}"; do
        mountpoint="/mnt/pve/$(basename $dataset)"
        mkdir -p "$mountpoint"

        # Create ZFS dataset if it doesn't exist
        pool=$(dirname $dataset)
        dataset_name=$(basename $dataset)
        if ! zfs list -H -o name | grep -q "^$pool/$dataset_name$"; then
            retry_command "zfs create -o mountpoint=$mountpoint $pool/$dataset_name"
            echo "[$(date)] Created ZFS dataset: $pool/$dataset_name with mountpoint $mountpoint" >> "$LOGFILE"
        fi

        # Add NFS exports for the datasets
        export_line="$mountpoint ${NFS_SUBNET}($NFS_EXPORT_OPTIONS)"
        if ! grep -q "^$export_line\$" /etc/exports; then
            echo "$export_line" >> /etc/exports || { echo "Error: Failed to update NFS exports." | tee -a "$LOGFILE"; exit 1; }
        fi

        # Export the new configuration and verify
        retry_command "exportfs -rav"
        echo "[$(date)] Added NFS export for $dataset" >> "$LOGFILE"

        # Verify NFS exports directly in /etc/exports
        if ! grep -q "$mountpoint" /etc/exports; then
            echo "Error: Failed to verify NFS export configuration for $mountpoint." | tee -a "$LOGFILE"
            exit 1
        fi

        # Add Proxmox NFS storage using common functions
        retry_command "pvesm add nfs --server $PROXMOX_NFS_SERVER --share $mountpoint --content images"
        echo "[$(date)] Added Proxmox NFS storage: $mountpoint" >> "$LOGFILE"
    done

    # Verify the final NFS export status
    verify_nfs_exports
}

# Simplified function to check for NFS exports in /etc/exports and log results
verify_nfs_exports() {
    if ! exportfs -v; then
        echo "Error: Failed to verify NFS exports" | tee -a "$LOGFILE"
        exit 1
    fi

    # Verify that the datasets are correctly exported
    for dataset in "${NFS_DATASET_LIST[@]}"; do
        mountpoint="/mnt/pve/$(basename $dataset)"
        if ! exportfs -v | grep -q "$mountpoint "; then
            echo "Error: NFS export verification failed for $mountpoint" | tee -a "$LOGFILE"
            exit 1
        fi
    done

    echo "[$(date)] Verified all NFS exports successfully" >> "$LOGFILE"
}

# Main execution using common functions
main() {
    check_root
    setup_logging
    check_pvesm
    prompt_for_subnet
    check_network
    install_prerequisites
    configure_nfs
    verify_nfs_exports

    echo "[$(date)] Completed NFS server configuration" >> "$LOGFILE"
}

main