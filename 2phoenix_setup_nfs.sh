#!/bin/bash

# phoenix_setup_nfs.sh
# Installs and configures NFS server on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Ensure script runs as root using common function
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging using the configuration setup_logging function
setup_logging() {
    mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR"; exit 1; }
    touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE"; exit 1; }
    chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE"; exit 1; }
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
}

# Prompt for network subnet using common functions
prompt_for_subnet() {
    read -p "Enter network subnet for NFS (default: ${DEFAULT_SUBNET}):" NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET" | tee -a "$LOGFILE"
        exit 1
    fi
}

# Install required NFS packages using common functions
install_prerequisites() {
    if ! check_package nfs-kernel-server; then
        retry_command "apt-get update && apt-get install -y nfs-kernel-server nfs-common ufw"
        echo "[$(date)] Installed NFS prerequisites" >> "$LOGFILE"
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

# Configure NFS server using common functions
configure_nfs() {
    echo "Configuring NFS exports..." | tee -a "$LOGFILE"

    create_mount_point() {
        local dataset="$1"
        if ! grep -q "nfs: $dataset" /etc/pve/storage.cfg; then
            retry_command "mkdir -p /mnt/pve/$dataset"
            pvesm add nfs "$dataset" -server "$PROXMOX_NFS_SERVER" -export "/$pool/$dataset" -path "/mnt/pve/$dataset" -content "$content" || {
                echo "Warning: Failed to add NFS storage for $pool/$dataset, continuing..." | tee -a "$LOGFILE"
                return
            }
        fi
    }

    for dataset in shared-prod-data shared-prod-data-sync shared-test-data shared-test-data-sync shared-backups shared-iso shared-bulk-data; do
        if [[ $dataset == shared-prod-data* ]]; then
            pool="quickOS"
            content="backup,iso"
        else
            pool="fastData"
            content=$([[ $dataset == shared-iso ]] && echo "iso,vztmpl" || echo "backup,iso")
        fi

        create_mount_point "$dataset"
    done

    # Update NFS exports using common functions
    update_nfs_exports() {
        grep -v "/quickOS/" /etc/exports > /tmp/exports.tmp || true
        for dataset in shared-prod-data shared-prod-data-sync; do
            sync_option=$([[ $dataset == shared-prod-data-sync ]] && echo "sync" || echo "async")
            echo "/quickOS/$dataset $NFS_SUBNET(rw,$sync_option,no_subtree_check,no_root_squash)" >> /tmp/exports.tmp

            if ! grep -q "\[$dataset\]" /etc/samba/smb.conf; then
                cat << EOF >> /etc/samba/smb.conf
[$dataset]
   path = /quickOS/$dataset
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
            fi
        done

        retry_command "mv /tmp/exports.tmp /etc/exports"
        retry_command "exportfs -ra"
    }

    update_nfs_exports

    # Verify NFS exports using common functions
    verify_nfs_exports() {
        for dataset in quickOS/shared-prod-data quickOS/shared-prod-data-sync fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
            mountpoint="/${dataset//\//\/}"
            if ! exportfs -v | grep "$mountpoint" > /dev/null; then
                echo "Error: NFS export for $mountpoint not found or misconfigured" | tee -a "$LOGFILE"
                exit 1
            fi
        done

        echo "Proxmox storage configuration completed." | tee -a "$LOGFILE"
    }

    verify_nfs_exports
}

# Main execution using common functions
main() {
    check_root
    setup_logging
    prompt_for_subnet
    install_prerequisites
    configure_nfs
}

main