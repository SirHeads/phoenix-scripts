#!/bin/bash

# phoenix_setup_zfs_datasets.sh
# Configures ZFS datasets for quickOS and fastData pools and sets up NFS/Samba shares
# Version: 1.0.13
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_zfs_datasets.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run after phoenix_setup_nfs.sh and phoenix_setup_samba.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
PROXMOX_NFS_SERVER="10.0.0.13" # Host IP for NFS server
DEFAULT_SUBNET="10.0.0.0/24" # Default network subnet

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging
setup_logging() {
    touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting ZFS dataset setup at $(date)"
}

# Prompt for network subnet
prompt_for_subnet() {
    echo "Enter network subnet for ZFS datasets (default: $DEFAULT_SUBNET):"
    read -r NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET"
        exit 1
    fi
}

# Configure firewall for Proxmox and NFS
configure_firewall_proxmox() {
    echo "Configuring firewall for SSH, Proxmox web UI, and NFS..." | tee -a "$LOGFILE"
    retry_command "ufw allow from 10.0.0.0/24 to any port 22 proto tcp" || { echo "Failed to set firewall rule for SSH from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 192.168.1.0/24 to any port 22 proto tcp" || { echo "Failed to set firewall rule for SSH from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 10.0.0.0/24 to any port 8006 proto tcp" || { echo "Failed to set firewall rule for Proxmox UI from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 192.168.1.0/24 to any port 8006 proto tcp" || { echo "Failed to set firewall rule for Proxmox UI from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 10.0.0.0/24 to any port 111 proto tcp" || { echo "Failed to set firewall rule for NFS port 111 from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 10.0.0.0/24 to any port 2049 proto tcp" || { echo "Failed to set firewall rule for NFS port 2049 from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    retry_command "ufw allow from 127.0.0.1 to any port 2049 proto tcp" || { echo "Failed to set firewall rule for NFS port 2049 from localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw status | grep -E "22|8006|111|2049" || { echo "Failed to verify firewall rules" | tee -a "$LOGFILE"; exit 1; }
}

# Prompt for Samba credentials
prompt_for_smb_credentials() {
    echo "Enter Samba username (e.g., heads):"
    read -r SMB_USER
    if [[ -z "$SMB_USER" ]]; then
        echo "Error: Samba username cannot be empty"
        exit 1
    fi
    echo "Enter Samba password (input hidden):"
    read -r -s SMB_PASSWORD
    if [[ -z "$SMB_PASSWORD" ]]; then
        echo "Error: Samba password cannot be empty"
        exit 1
    fi
    echo "Confirm Samba password (input hidden):"
    read -r -s SMB_PASSWORD_CONFIRM
    if [[ "$SMB_PASSWORD" != "$SMB_PASSWORD_CONFIRM" ]]; then
        echo "Error: Samba passwords do not match"
        exit 1
    fi
}

# Configure quickOS datasets and shares
configure_quickOS_datasets() {
    echo "Creating quickOS datasets and configuring shares..." | tee -a "$LOGFILE"
    for dataset in disks-vm disks-lxc shared-prod-data shared-prod-data-sync; do
        if zfs list -H -o name | grep -q "^quickOS/$dataset$"; then
            echo "Dataset quickOS/$dataset already exists, skipping creation" | tee -a "$LOGFILE"
        else
            zfs create -o mountpoint=/quickOS/$dataset quickOS/$dataset || {
                echo "Error: Failed to create quickOS/$dataset dataset"
                exit 1
            }
        fi
        groupadd -f sambashare
        usermod -aG sambashare $SMB_USER
        chmod 775 /quickOS/$dataset
        chown root:sambashare /quickOS/$dataset
        zfs set sharenfs=off quickOS/$dataset || { echo "Error: Failed to set sharenfs=off for quickOS/$dataset"; exit 1; }
    done
    # Update NFS exports
    grep -v "/quickOS/" /etc/exports > /tmp/exports.tmp || true
    for dataset in shared-prod-data shared-prod-data-sync; do
        # Use sync for shared-prod-data-sync for database workloads
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
    mv /tmp/exports.tmp /etc/exports
    exportfs -ra || { echo "Error: Failed to export NFS shares"; exit 1; }
    systemctl restart smbd nmbd || { echo "Error: Failed to restart Samba services"; exit 1; }
}

# Configure fastData datasets and shares
configure_fastData_datasets() {
    echo "Creating fastData datasets and configuring shares..." | tee -a "$LOGFILE"
    for dataset in shared-test-data shared-test-data-sync shared-backups shared-iso shared-bulk-data; do
        if zfs list -H -o name | grep -q "^fastData/$dataset$"; then
            echo "Dataset fastData/$dataset already exists, skipping creation" | tee -a "$LOGFILE"
        else
            zfs create -o mountpoint=/fastData/$dataset fastData/$dataset || {
                echo "Error: Failed to create fastData/$dataset dataset"
                exit 1
            }
        fi
        groupadd -f sambashare
        usermod -aG sambashare $SMB_USER
        chmod 775 /fastData/$dataset
        chown root:sambashare /fastData/$dataset
        zfs set sharenfs=off fastData/$dataset || { echo "Error: Failed to set sharenfs=off for fastData/$dataset"; exit 1; }
    done
    # Update NFS exports
    grep -v "/fastData/" /etc/exports > /tmp/exports.tmp || true
    for dataset in shared-test-data shared-test-data-sync shared-backups shared-iso shared-bulk-data; do
        # Use sync for shared-test-data-sync for database workloads
        sync_option=$([[ $dataset == shared-test-data-sync ]] && echo "sync" || echo "async")
        echo "/fastData/$dataset $NFS_SUBNET(rw,$sync_option,no_subtree_check,no_root_squash)" >> /tmp/exports.tmp
        if ! grep -q "\[$dataset\]" /etc/samba/smb.conf; then
            cat << EOF >> /etc/samba/smb.conf
[$dataset]
   path = /fastData/$dataset
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
        fi
    done
    mv /tmp/exports.tmp /etc/exports
    exportfs -ra || { echo "Error: Failed to export NFS shares"; exit 1; }
    systemctl restart smbd nmbd || { echo "Error: Failed to restart Samba services"; exit 1; }
}

# Register datasets with Proxmox
configure_proxmox_storage() {
    echo "Registering datasets with Proxmox storage..." | tee -a "$LOGFILE"
    # Ensure /mnt/pve exists and is writable
    mkdir -p /mnt/pve || { echo "Error: Failed to create /mnt/pve"; exit 1; }
    chmod 775 /mnt/pve
    chown root:sambashare /mnt/pve
    if mountpoint -q /mnt/pve; then
        umount /mnt/pve 2>/dev/null || true
    fi
    if ! grep -q "zfspool: quickOS" /etc/pve/storage.cfg; then
        pvesm add zfspool quickOS -pool quickOS -content images,rootdir -sparse 1 || {
            echo "Error: Failed to add quickOS to Proxmox storage"
            exit 1
        }
    fi
    if ! grep -q "zfspool: fastData" /etc/pve/storage.cfg; then
        pvesm add zfspool fastData -pool fastData -content images,rootdir -sparse 1 || {
            echo "Error: Failed to add fastData to Proxmox storage"
            exit 1
        }
    fi
    for dataset in shared-prod-data shared-prod-data-sync shared-test-data shared-test-data-sync shared-backups shared-iso shared-bulk-data; do
        if [[ $dataset == shared-prod-data* ]]; then
            pool="quickOS"
            content="backup,iso"
        else
            pool="fastData"
            content=$([[ $dataset == shared-iso ]] && echo "iso,vztmpl" || echo "backup,iso")
        fi
        if ! grep -q "nfs: $dataset" /etc/pve/storage.cfg; then
            mkdir -p /mnt/pve/$dataset || { echo "Error: Failed to create /mnt/pve/$dataset"; exit 1; }
            pvesm add nfs $dataset -server $PROXMOX_NFS_SERVER -export /$pool/$dataset -path /mnt/pve/$dataset -content $content || {
                echo "Warning: Failed to add NFS storage for $pool/$dataset, continuing..." | tee -a "$LOGFILE"
                continue
            }
        fi
    done
    echo "Proxmox storage configuration completed" | tee -a "$LOGFILE"
}

# Verify dataset mountpoints
verify_mountpoints() {
    echo "Verifying dataset mountpoints..." | tee -a "$LOGFILE"
    for dataset in quickOS/disks-vm quickOS/disks-lxc quickOS/shared-prod-data quickOS/shared-prod-data-sync fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
        mountpoint="/${dataset/\//\/}"
        if ! mountpoint -q "$mountpoint"; then
            echo "Error: Mountpoint $mountpoint is not a valid ZFS mountpoint"
            exit 1
        fi
        echo "Mountpoint $mountpoint for $dataset verified"
    done
}

# Verify NFS exports
verify_nfs_exports() {
    echo "Verifying NFS exports..." | tee -a "$LOGFILE"
    echo "Current NFS exports:" | tee -a "$LOGFILE"
    exportfs -v | tee -a "$LOGFILE"
    for dataset in quickOS/shared-prod-data quickOS/shared-prod-data-sync fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
        mountpoint="/${dataset/\//\/}"
        if ! exportfs -v | grep "$mountpoint" > /dev/null; then
            echo "Error: NFS export for $mountpoint not found or misconfigured" | tee -a "$LOGFILE"
            exit 1
        fi
        echo "NFS export for $mountpoint verified" | tee -a "$LOGFILE"
    done
}

# Verify dataset responsiveness
verify_datasets() {
    echo "Verifying dataset responsiveness..." | tee -a "$LOGFILE"
    for dataset in quickOS/disks-vm quickOS/disks-lxc quickOS/shared-prod-data quickOS/shared-prod-data-sync fastData/shared-test-data fastData/shared-test-data-sync fastData/shared-backups fastData/shared-iso fastData/shared-bulk-data; do
        mountpoint="/${dataset/\//\/}"
        # Local write test
        touch "$mountpoint/testfile" || {
            echo "Error: Failed to write to $mountpoint"
            exit 1
        }
        rm "$mountpoint/testfile"
        echo "Local write to $mountpoint successful"
        # NFS test for shared datasets
        if [[ $dataset == quickOS/shared-prod-data* || $dataset == fastData/shared-* ]]; then
            mkdir -p "/mnt/nfs-test-$dataset"
            retry_command "mount -t nfs $PROXMOX_NFS_SERVER:$mountpoint /mnt/nfs-test-$dataset" || {
                echo "Error: Command failed after 3 attempts: mount -t nfs $PROXMOX_NFS_SERVER:$mountpoint /mnt/nfs-test-$dataset"
                echo "Error output: $(mount -t nfs $PROXMOX_NFS_SERVER:$mountpoint /mnt/nfs-test-$dataset 2>&1)"
                rm -rf "/mnt/nfs-test-$dataset"
                exit 1
            }
            touch "/mnt/nfs-test-$dataset/testfile" || {
                echo "Error: Failed to write to NFS mount $mountpoint"
                umount "/mnt/nfs-test-$dataset"
                rm -rf "/mnt/nfs-test-$dataset"
                exit 1
            }
            rm "/mnt/nfs-test-$dataset/testfile"
            umount "/mnt/nfs-test-$dataset"
            rm -rf "/mnt/nfs-test-$dataset"
            echo "NFS access to $mountpoint successful"
        fi
        # Samba test for shared datasets
        if [[ $dataset == quickOS/shared-prod-data* || $dataset == fastData/shared-* ]]; then
            dataset_name=$(basename "$dataset")
            echo "test" > /tmp/samba-test-file
            chown "$SMB_USER":"$SMB_USER" /tmp/samba-test-file
            chmod 644 /tmp/samba-test-file
            echo "Enter Samba password for $SMB_USER to test $dataset_name:"
            smbclient //localhost/$dataset_name -U $SMB_USER -c 'put /tmp/samba-test-file testfile' || {
                echo "Error: Failed to upload to Samba share $dataset_name" | tee -a "$LOGFILE"
                rm -rf /tmp/samba-test-file
                exit 1
            }
            rm -rf /tmp/samba-test-file
            echo "Samba access to $dataset_name successful" | tee -a "$LOGFILE"
        fi
    done
}

# Main execution
main() {
    check_root
    setup_logging
    prompt_for_subnet
    configure_firewall_proxmox
    prompt_for_smb_credentials
    configure_quickOS_datasets
    configure_fastData_datasets
    configure_proxmox_storage
    verify_mountpoints
    verify_nfs_exports
    verify_datasets
    echo "ZFS dataset setup and verification completed successfully at $(date)"
}

main