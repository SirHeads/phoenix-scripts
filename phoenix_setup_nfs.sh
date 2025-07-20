#!/bin/bash

# phoenix_setup_nfs.sh
# Installs and configures NFS server and firewall for Proxmox setup
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_nfs.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run before phoenix_setup_samba.sh and phoenix_setup_zfs_datasets.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
DEFAULT_SUBNET="10.0.0.0/24" # Default network subnet
PROXMOX_NFS_SERVER="10.0.0.13" # Host IP for NFS server

# Ensure script runs as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root." | tee -a "$LOGFILE"
        exit 1
    fi
}

# Initialize logging
setup_logging() {
    if [[ -z "$LOGFILE" ]]; then
        LOGFILE="/var/log/proxmox_setup.log"
    fi
    touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting NFS setup at $(date)"
}

# Prompt for network subnet
prompt_for_subnet() {
    echo "Enter network subnet for NFS (default: $DEFAULT_SUBNET):"
    read -r NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET"
        exit 1
    fi
}

# Install required NFS packages
install_prerequisites() {
    echo "Installing NFS prerequisites..."
    apt-get update
    apt-get install -y nfs-kernel-server nfs-common ufw || {
        echo "Failed to install NFS prerequisites"
        exit 1
    }
}

# Check network connectivity
check_network() {
    echo "Checking network connectivity..."
    # Check localhost resolution
    if ! ping -c 1 localhost >/dev/null 2>&1; then
        echo "Warning: Hostname 'localhost' does not resolve to 127.0.0.1. Check /etc/hosts."
    fi
    # Check if PROXMOX_NFS_SERVER is reachable
    if ! ping -c 1 "$PROXMOX_NFS_SERVER" >/dev/null 2>&1; then
        echo "Error: NFS server IP $PROXMOX_NFS_SERVER is not reachable."
        exit 1
    fi
    # Check if an interface has an IP in NFS_SUBNET
    if ! ip addr show | grep -q "inet.*$NFS_SUBNET"; then
        echo "Warning: Network subnet $NFS_SUBNET not detected on any interface. NFS may not work as expected."
    else
        echo "Network subnet $NFS_SUBNET detected on interface."
    fi
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Warning: No internet connectivity detected. Package installation may fail."
    fi
}

# Configure NFS server
configure_nfs() {
    echo "Configuring NFS server..."
    # Create a minimal /etc/exports file (no dataset-specific paths)
    cat << EOF > /etc/exports
# NFS exports will be configured in phoenix_setup_zfs_datasets.sh
EOF
    exportfs -ra || { echo "Failed to export NFS shares"; exit 1; }
    systemctl enable --now rpcbind nfs-kernel-server || { echo "Failed to enable NFS services"; exit 1; }
}

# Verify NFS services and responsiveness
verify_nfs() {
    echo "Verifying NFS services and responsiveness..."
    # Check if services are running
    for service in rpcbind nfs-kernel-server; do
        if ! systemctl is-active --quiet "$service"; then
            echo "Error: $service is not running"
            exit 1
        fi
        if ! systemctl is-enabled --quiet "$service"; then
            echo "Error: $service is not enabled"
            exit 1
        fi
        echo "$service is running and enabled"
    done
    # Check if required ports are listening
    for port in 111 2049; do
        if ! ss -tuln | grep -q ":$port "; then
            echo "Error: Port $port is not listening"
            exit 1
        fi
        echo "Port $port is listening"
    done
    # Test NFS responsiveness with a temporary export
    mkdir -p /tmp/nfs-test
    chmod 755 /tmp/nfs-test
    echo "/tmp/nfs-test $NFS_SUBNET(rw,async,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra || { echo "Failed to export temporary NFS share"; exit 1; }
    mkdir -p /mnt/nfs-test
    mount -t nfs "$PROXMOX_NFS_SERVER:/tmp/nfs-test" /mnt/nfs-test || {
        echo "Error: Failed to mount temporary NFS share"
        rm -rf /mnt/nfs-test
        exit 1
    }
    touch /mnt/nfs-test/testfile || {
        echo "Error: Failed to write to temporary NFS share"
        umount /mnt/nfs-test
        rm -rf /mnt/nfs-test
        exit 1
    }
    umount /mnt/nfs-test
    rm -rf /mnt/nfs-test
    rm -rf /tmp/nfs-test
    sed -i '/\/tmp\/nfs-test/d' /etc/exports
    exportfs -ra
    echo "NFS server is responsive"
}

# Configure firewall for NFS
configure_firewall_nfs() {
    echo "Configuring firewall for NFS, SSH, and Proxmox UI..." | tee -a "$LOGFILE"
    ufw allow from "$NFS_SUBNET" to any port 111 proto tcp || { echo "Failed to set firewall rule for RPC" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from "$NFS_SUBNET" to any port 2049 proto tcp || { echo "Failed to set firewall rule for NFS" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 127.0.0.1 to any port 2049 proto tcp || { echo "Failed to set firewall rule for NFS localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 10.0.0.0/24 to any port 22 proto tcp || { echo "Failed to set firewall rule for SSH from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 192.168.1.0/24 to any port 22 proto tcp || { echo "Failed to set firewall rule for SSH from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 10.0.0.0/24 to any port 8006 proto tcp || { echo "Failed to set firewall rule for Proxmox UI from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 192.168.1.0/24 to any port 8006 proto tcp || { echo "Failed to set firewall rule for Proxmox UI from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw enable || { echo "Failed to enable firewall" | tee -a "$LOGFILE"; exit 1; }
    ufw status | grep -E "111|2049|22|8006" || { echo "Failed to verify firewall rules" | tee -a "$LOGFILE"; exit 1; }
}

# Main execution
main() {
    check_root
    setup_logging
    prompt_for_subnet
    check_network
    install_prerequisites
    configure_nfs
    configure_firewall_nfs
    verify_nfs
    echo "NFS setup and verification completed successfully at $(date)"
}

main