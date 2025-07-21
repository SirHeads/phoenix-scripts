#!/bin/bash

# phoenix_setup_nfs.sh
# Installs and configures NFS server on Proxmox VE
# Version: 1.0.4
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
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

    local nfs_datasets=("shared-prod-data" "shared-prod-data-sync")
    for dataset in "${nfs_datasets[@]}"; do
        mountpoint="/mnt/pve/$dataset"
        mkdir -p "$mountpoint"

        # Create ZFS datasets on rpool and quickOS pools
        if ! zfs list -H -o name | grep -q "^rpool/$dataset$"; then
            retry_command "zfs create -o mountpoint=$mountpoint rpool/$dataset"
            echo "[$(date)] Created ZFS dataset: rpool/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
        fi

        if ! zfs list -H -o name | grep -q "^quickOS/$dataset$"; then
            retry_command "zfs create -o mountpoint=$mountpoint quickOS/$dataset"
            echo "[$(date)] Created ZFS dataset: quickOS/$dataset with mountpoint $mountpoint" >> "$LOGFILE"
        fi

        # Add NFS exports for the datasets
        export_line="$mountpoint ${NFS_SUBNET}(rw,sync,no_subtree_check)"
        if ! grep -q "^$export_line\$" /etc/exports; then
            echo "$export_line" >> /etc/exports || { echo "Error: Failed to update NFS exports." | tee -a "$LOGFILE"; exit 1; }
        fi

        # Export the new configuration and verify
        retry_command "exportfs -rav"
        echo "[$(date)] Added NFS export for $dataset" >> "$LOGFILE"

        # Verify NFS exports directly in /etc/exports without complex regex
        if ! grep -q "/mnt/pve/$dataset" /etc/exports; then
            echo "Error: Failed to verify NFS export configuration." | tee -a "$LOGFILE"
            exit 1
        fi
    done

    # Add Proxmox NFS storage using common functions (assuming pvesm is available)
    for dataset in "${nfs_datasets[@]}"; do
        retry_command "pvesm add nfs --server $PROXMOX_NFS_SERVER --share /mnt/pve/$dataset --content images"
        echo "[$(date)] Added Proxmox NFS storage: /mnt/pve/$dataset" >> "$LOGFILE"
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

    # Verify that the datasets are correctly exported without complex regex
    for dataset in shared-prod-data shared-prod-data-sync; do
        if ! exportfs -v | grep -q "/mnt/pve/$dataset "; then
            echo "Error: NFS export verification failed for /mnt/pve/$dataset" | tee -a "$LOGFILE"
            exit 1
        fi
    done

    echo "[$(date)] Verified all NFS exports successfully" >> "$LOGFILE"
}

# Main execution using common functions
main() {
    check_root
    setup_logging
    prompt_for_subnet
    install_prerequisites
    configure_nfs
    verify_nfs_exports

    echo "[$(date)] Completed NFS server configuration" >> "$LOGFILE"
}

main