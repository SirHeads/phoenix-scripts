#!/bin/bash

# phoenix_setup_zfs_pools.sh
# Configures ZFS pools (quickOS, fastData) for NVMe drives and tunes ARC cache.
# Version: 1.0.2
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_pools.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run before phoenix_setup_zfs_datasets.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
ARC_MAX=$((24 * 1024 * 1024 * 1024)) # 24GB ARC cache for 96GB RAM system

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging
setup_logging() {
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting ZFS pool setup at $(date)" | tee -a "$LOGFILE"
}

# Check ZFS version for autotrim support
check_zfs_version() {
    echo "Checking ZFS version..." | tee -a "$LOGFILE"
    ZFS_VERSION=$(zfs version | head -n1 | cut -d'-' -f2)
    if [[ "$ZFS_VERSION" < "2.0" ]]; then
        echo "Warning: ZFS version $ZFS_VERSION does not support autotrim. Will rely on periodic fstrim." | tee -a "$LOGFILE"
        AUTOTRIM_SUPPORTED=false
    else
        echo "ZFS version $ZFS_VERSION supports autotrim." | tee -a "$LOGFILE"
        AUTOTRIM_SUPPORTED=true
    fi
}

# Prompt for NVMe drives
prompt_for_drives() {
    echo "Available NVMe drives:" | tee -a "$LOGFILE"
    lsblk -d -o NAME,SIZE,MODEL | grep nvme
    echo "Select two NVMe drives for quickOS (mirrored, 2TB each, e.g., /dev/nvme0n1 /dev/nvme2n1):"
    read -r -p "Enter two drive paths (space-separated): " quickos_drive1 quickos_drive2
    if [[ ! -b "$quickos_drive1" || ! -b "$quickos_drive2" ]]; then
        echo "Error: Invalid or non-existent drives: $quickos_drive1, $quickos_drive2" | tee -a "$LOGFILE"
        exit 1
    fi
    QUICKOS_2TB_DRIVES=("$quickos_drive1" "$quickos_drive2")

    echo "Select one NVMe drive for fastData (2TB, e.g., /dev/nvme1n1):"
    read -r -p "Enter drive path: " fastdata_drive
    if [[ ! -b "$fastdata_drive" ]]; then
        echo "Error: Invalid or non-existent drive: $fastdata_drive" | tee -a "$LOGFILE"
        exit 1
    fi
    FASTDATA_2TB_DRIVE="$fastdata_drive"
}

# Check if drives are in use
check_drives_free() {
    echo "Checking if drives are free..." | tee -a "$LOGFILE"
    for drive in "${QUICKOS_2TB_DRIVES[@]}" "$FASTDATA_2TB_DRIVE"; do
        if zpool status | grep -q "$drive"; then
            echo "Error: Drive $drive is part of an existing ZFS pool. Destroy the pool first." | tee -a "$LOGFILE"
            exit 1
        fi
        if mount | grep -q "$drive"; then
            echo "Error: Drive $drive is mounted. Unmount it first." | tee -a "$LOGFILE"
            exit 1
        fi
        if pvdisplay | grep -q "$drive"; then
            echo "Error: Drive $drive is part of an LVM physical volume. Remove it first." | tee -a "$LOGFILE"
            exit 1
        fi
        if lsof "$drive" > /dev/null 2>&1; then
            echo "Error: Drive $drive is in use by a process. Stop processes first." | tee -a "$LOGFILE"
            exit 1
        fi
    done
}

# Confirm drive wiping
confirm_wipe_drives() {
    echo "WARNING: This script will wipe the following drives:" | tee -a "$LOGFILE"
    echo "quickOS (mirror): ${QUICKOS_2TB_DRIVES[*]}" | tee -a "$LOGFILE"
    echo "fastData (single): $FASTDATA_2TB_DRIVE" | tee -a "$LOGFILE"
    read -p "Proceed with wiping drives? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted by user." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Wipe drives
wipe_drives() {
    echo "Wiping drives..." | tee -a "$LOGFILE"
    for drive in "${QUICKOS_2TB_DRIVES[@]}" "$FASTDATA_2TB_DRIVE"; do
        if [[ -b "$drive" ]]; then
            wipefs -a "$drive" || { echo "Failed to wipe $drive" | tee -a "$LOGFILE"; exit 1; }
        else
            echo "Error: Drive $drive not found." | tee -a "$LOGFILE"
            exit 1
        fi
    done
}

# Create ZFS pools
create_zfs_pools() {
    echo "Checking for existing ZFS pools..." | tee -a "$LOGFILE"
    
    # Convert raw device paths to /dev/disk/by-id/ paths
    local quickos_id1 quickos_id2 fastdata_id
    quickos_id1=$(ls -l /dev/disk/by-id/ | grep $(basename "$quickos_drive1") | awk '{print $9}' | head -1)
    quickos_id2=$(ls -l /dev/disk/by-id/ | grep $(basename "$quickos_drive2") | awk '{print $9}' | head -1)
    fastdata_id=$(ls -l /dev/disk/by-id/ | grep $(basename "$fastdata_drive") | awk '{print $9}' | head -1)
    
    if [[ -z "$quickos_id1" || -z "$quickos_id2" || -z "$fastdata_id" ]]; then
        echo "Error: Could not find /dev/disk/by-id/ paths for one or more drives" | tee -a "$LOGFILE"
        exit 1
    fi
    
    # Create or import quickOS pool
    if zpool status quickOS >/dev/null 2>&1; then
        echo "Warning: quickOS pool already exists, skipping creation" | tee -a "$LOGFILE"
        zpool import -d /dev/disk/by-id -f quickOS || {
            echo "Error: Failed to import existing quickOS pool" | tee -a "$LOGFILE"
            exit 1
        }
    else
        echo "Creating ZFS pool quickOS (mirror)..." | tee -a "$LOGFILE"
        if [[ "$AUTOTRIM_SUPPORTED" == "true" ]]; then
            zpool create -f -o ashift=12 -o autotrim=on quickOS mirror /dev/disk/by-id/"$quickos_id1" /dev/disk/by-id/"$quickos_id2" || {
                echo "Failed to create quickOS pool" | tee -a "$LOGFILE"
                exit 1
            }
        else
            zpool create -f -o ashift=12 quickOS mirror /dev/disk/by-id/"$quickos_id1" /dev/disk/by-id/"$quickos_id2" || {
                echo "Failed to create quickOS pool" | tee -a "$LOGFILE"
                exit 1
            }
            echo "Setting up periodic fstrim due to lack of autotrim support..." | tee -a "$LOGFILE"
            echo "15 3 * * * root fstrim /quickOS" > /etc/cron.d/fstrim_quickOS
        fi
        zfs set compression=lz4 atime=off quickOS || {
            echo "Failed to set properties on quickOS pool" | tee -a "$LOGFILE"
            exit 1
        }
        zpool export quickOS && zpool import -d /dev/disk/by-id quickOS || {
            echo "Failed to export/import quickOS to update cache" | tee -a "$LOGFILE"
            exit 1
        }
    fi

    # Create or import fastData pool
    if zpool status fastData >/dev/null 2>&1; then
        echo "Warning: fastData pool already exists, skipping creation" | tee -a "$LOGFILE"
        zpool import -d /dev/disk/by-id -f fastData || {
            echo "Error: Failed to import existing fastData pool" | tee -a "$LOGFILE"
            exit 1
        }
    else
        echo "Creating ZFS pool fastData (single)..." | tee -a "$LOGFILE"
        if [[ "$AUTOTRIM_SUPPORTED" == "true" ]]; then
            zpool create -f -o ashift=12 -o autotrim=on fastData /dev/disk/by-id/"$fastdata_id" || {
                echo "Failed to create fastData pool" | tee -a "$LOGFILE"
                exit 1
            }
        else
            zpool create -f -o ashift=12 fastData /dev/disk/by-id/"$fastdata_id" || {
                echo "Failed to create fastData pool" | tee -a "$LOGFILE"
                exit 1
            }
            echo "Setting up periodic fstrim for fastData..." | tee -a "$LOGFILE"
            echo "15 3 * * * root fstrim /fastData" > /etc/cron.d/fstrim_fastData
        fi
        zfs set compression=lz4 atime=off fastData || {
            echo "Failed to set properties on fastData pool" | tee -a "$LOGFILE"
            exit 1
        }
        zpool export fastData && zpool import -d /dev/disk/by-id fastData || {
            echo "Failed to export/import fastData to update cache" | tee -a "$LOGFILE"
            exit 1
        }
    fi
}

# Tune ARC cache
tune_arc() {
    echo "Tuning ARC cache to 24GB..." | tee -a "$LOGFILE"
    echo "$ARC_MAX" > /sys/module/zfs/parameters/zfs_arc_max
    echo "options zfs zfs_arc_max=$ARC_MAX" > /etc/modprobe.d/zfs.conf
}

# Main execution
main() {
    check_root
    setup_logging
    check_zfs_version
    prompt_for_drives
    check_drives_free
    confirm_wipe_drives
    wipe_drives
    create_zfs_pools
    tune_arc
    echo "ZFS pool setup completed successfully at $(date)" | tee -a "$LOGFILE"
}

main