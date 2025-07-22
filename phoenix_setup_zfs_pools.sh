#!/bin/bash

# phoenix_setup_zfs_pools.sh
# Configures ZFS pools (quickOS and fastData) on Proxmox VE for the Phoenix server.
# Version: 1.2.0
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_pools.sh [-q "quickos_drives"] [-f "fastdata_drive"]

# Log file
LOGFILE="/var/log/proxmox_setup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Function to check if the script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$TIMESTAMP] Verified script is running as root" >> "$LOGFILE"
}

# Ensure log file exists and is writable
touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
chmod 644 "$LOGFILE"
echo "[$TIMESTAMP] Initialized logging for phoenix_setup_zfs_pools.sh" >> "$LOGFILE"

# Function to execute commands with retries
retry_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "[$TIMESTAMP] Attempt $attempt/$max_attempts: $cmd" >> "$LOGFILE"
        eval $cmd
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Command succeeded: $cmd" >> "$LOGFILE"
            return 0
        fi
        echo "[$TIMESTAMP] Command failed, retrying ($attempt/$max_attempts): $cmd" >> "$LOGFILE"
        sleep 5
        ((attempt++))
    done
    echo "[$TIMESTAMP] Error: Command failed after $max_attempts attempts: $cmd" | tee -a "$LOGFILE"
    return 1
}

# Function to check if a drive is available
check_available_drives() {
    local drive="$1"
    if [ ! -b "/dev/$drive" ]; then
        echo "Error: Drive $drive does not exist" | tee -a "$LOGFILE"
        exit 1
    fi
    if zpool status | grep -q "$drive"; then
        echo "Error: Drive $drive is already part of a ZFS pool" | tee -a "$LOGFILE"
        exit 1
    fi
    # Log drive type
    DRIVE_TYPE=$(lsblk -d -o MODEL,TRAN | grep "^${drive}" | awk '{print $2}')
    if [[ -z "$DRIVE_TYPE" ]]; then
        echo "[$TIMESTAMP] Drive $drive type could not be determined, proceeding anyway" >> "$LOGFILE"
    else
        echo "[$TIMESTAMP] Drive $drive is of type $DRIVE_TYPE" >> "$LOGFILE"
    fi
    echo "[$TIMESTAMP] Verified that drive $drive is available" >> "$LOGFILE"
}

# Function to monitor NVMe wear
monitor_nvme_wear() {
    local drives="$@"
    if command -v smartctl >/dev/null 2>&1; then
        for drive in $drives; do
            if lsblk -d -o NAME,TRAN | grep "^${drive}" | grep -q "nvme"; then
                smartctl -a /dev/$drive | grep -E "Wear_Leveling|Media_Wearout" >> "$LOGFILE" 2>/dev/null
                echo "[$TIMESTAMP] NVMe wear stats for $drive logged" >> "$LOGFILE"
            fi
        done
    else
        echo "[$TIMESTAMP] smartctl not installed, skipping NVMe wear monitoring" >> "$LOGFILE"
    fi
}

# Function to check system RAM for ZFS ARC
check_system_ram() {
    local zfs_arc_max=8589934592  # 8GB in bytes
    local required_ram=$((zfs_arc_max * 2))
    local total_ram=$(free -b | awk '/Mem:/ {print $2}')
    if [[ $total_ram -lt $required_ram ]]; then
        echo "Warning: System RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is less than twice ZFS_ARC_MAX ($((zfs_arc_max / 1024 / 1024 / 1024)) GB). This may cause memory issues." | tee -a "$LOGFILE"
        read -p "Continue with current ZFS_ARC_MAX setting? (y/n): " RAM_CONFIRMATION
        if [[ "$RAM_CONFIRMATION" != "y" && "$RAM_CONFIRMATION" != "Y" ]]; then
            echo "Error: Aborted due to insufficient RAM for ZFS_ARC_MAX" | tee -a "$LOGFILE"
            exit 1
        fi
    fi
    echo "[$TIMESTAMP] Verified system RAM ($((total_ram / 1024 / 1024 / 1024)) GB) is sufficient for ZFS_ARC_MAX" >> "$LOGFILE"
    echo "$zfs_arc_max" > /sys/module/zfs/parameters/zfs_arc_max || { echo "Error: Failed to set zfs_arc_max to $zfs_arc_max" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Set zfs_arc_max to $zfs_arc_max bytes" >> "$LOGFILE"
}

# Parse command-line arguments
while getopts "q:f:" opt; do
    case $opt in
        q) QUICKOS_DRIVES=($OPTARG);;
        f) FASTDATA_DRIVE="$OPTARG";;
        \?) echo "Invalid option: -$OPTARG" | tee -a "$LOGFILE"; exit 1;;
        :) echo "Option -$OPTARG requires an argument" | tee -a "$LOGFILE"; exit 1;;
    esac
done

# Set defaults and prompt if not provided
QUICKOS_DRIVES=(${QUICKOS_DRIVES[@]:-nvme1n1 nvme2n1})
FASTDATA_DRIVE=${FASTDATA_DRIVE:-nvme0n1}
if [ ${#QUICKOS_DRIVES[@]} -eq 0 ]; then
    read -p "Enter the drives for quickOS pool (e.g., nvme1n1 nvme2n1): " QUICKOS_DRIVES_INPUT
    QUICKOS_DRIVES=($QUICKOS_DRIVES_INPUT)
fi
if [ -z "$FASTDATA_DRIVE" ]; then
    read -p "Enter the drive for fastData pool (e.g., nvme0n1): " FASTDATA_DRIVE
fi

# Validate quickOS drives
if [ ${#QUICKOS_DRIVES[@]} -ne 2 ]; then
    echo "Error: Exactly two drives must be specified for quickOS mirror" | tee -a "$LOGFILE"
    exit 1
fi
if [ "${QUICKOS_DRIVES[0]}" = "${QUICKOS_DRIVES[1]}" ] || [ "${QUICKOS_DRIVES[0]}" = "$FASTDATA_DRIVE" ] || [ "${QUICKOS_DRIVES[1]}" = "$FASTDATA_DRIVE" ]; then
    echo "Error: All drives must be distinct, got quickOS: ${QUICKOS_DRIVES[*]}, fastData: $FASTDATA_DRIVE" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set QUICKOS_DRIVES to ${QUICKOS_DRIVES[*]}" >> "$LOGFILE"
echo "[$TIMESTAMP] Set FASTDATA_DRIVE to $FASTDATA_DRIVE" >> "$LOGFILE"

# Install ZFS packages
if ! command -v zpool >/dev/null 2>&1; then
    retry_command "apt-get install -y zfsutils-linux smartmontools" || { echo "Error: Failed to install zfsutils-linux and smartmontools" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Installed zfsutils-linux and smartmontools" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] ZFS utilities already installed, skipping installation" >> "$LOGFILE"
fi

# Check available drives
for drive in "${QUICKOS_DRIVES[@]}" "$FASTDATA_DRIVE"; do
    check_available_drives "$drive"
done

# Wipe existing partitions
for drive in "${QUICKOS_DRIVES[@]}" "$FASTDATA_DRIVE"; do
    retry_command "wipefs -a /dev/$drive" || { echo "Error: Failed to wipe partitions on /dev/$drive" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Wiped partitions on /dev/$drive" >> "$LOGFILE"
done

# Create ZFS pools
if zpool list quickOS >/dev/null 2>&1; then
    echo "[$TIMESTAMP] Pool quickOS already exists, skipping creation" >> "$LOGFILE"
else
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off quickOS mirror ${QUICKOS_DRIVES[0]} ${QUICKOS_DRIVES[1]}" || { echo "Error: Failed to create quickOS pool" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Created ZFS pool quickOS on ${QUICKOS_DRIVES[*]}" >> "$LOGFILE"
fi

if zpool list fastData >/dev/null 2>&1; then
    echo "[$TIMESTAMP] Pool fastData already exists, skipping creation" >> "$LOGFILE"
else
    retry_command "zpool create -f -o autotrim=on -O compression=lz4 -O atime=off fastData $FASTDATA_DRIVE" || { echo "Error: Failed to create fastData pool" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Created ZFS pool fastData on $FASTDATA_DRIVE" >> "$LOGFILE"
fi

# Monitor NVMe wear
monitor_nvme_wear "${QUICKOS_DRIVES[*]}" "$FASTDATA_DRIVE"

# Check system RAM and set ARC limit
check_system_ram

echo "[$TIMESTAMP] Successfully completed phoenix_setup_zfs_pools.sh" >> "$LOGFILE"
exit 0