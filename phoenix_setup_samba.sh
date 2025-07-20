#!/bin/bash

# phoenix_setup_samba.sh
# Installs and configures Samba server, user, and firewall for Proxmox setup
# Version: 1.0.4
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_setup_samba.sh
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup
# Run after phoenix_setup_nfs.sh and before phoenix_setup_zfs_datasets.sh

# Exit on any error
set -e

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

# Constants
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
    # Use LOGFILE from common.sh
    touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    echo "Starting Samba setup at $(date)"
}

# Prompt for network subnet
prompt_for_subnet() {
    echo "Enter network subnet for Samba (default: $DEFAULT_SUBNET):"
    read -r NFS_SUBNET
    NFS_SUBNET=${NFS_SUBNET:-$DEFAULT_SUBNET}
    if ! [[ "$NFS_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format: $NFS_SUBNET"
        exit 1
    fi
}

# Install required Samba packages
install_prerequisites() {
    echo "Installing Samba prerequisites..."
    apt-get update
    apt-get install -y samba smbclient ufw || {
        echo "Failed to install Samba prerequisites"
        exit 1
    }
}

# Configure firewall for Samba, SSH, and Proxmox UI
configure_firewall_samba() {
    echo "Configuring firewall for Samba, SSH, and Proxmox UI..." | tee -a "$LOGFILE"
    ufw allow from "$NFS_SUBNET" to any port 137 proto udp || { echo "Failed to set firewall rule for Samba UDP 137" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from "$NFS_SUBNET" to any port 138 proto udp || { echo "Failed to set firewall rule for Samba UDP 138" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from "$NFS_SUBNET" to any port 139 proto tcp || { echo "Failed to set firewall rule for Samba TCP 139" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from "$NFS_SUBNET" to any port 445 proto tcp || { echo "Failed to set firewall rule for Samba TCP 445" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 127.0.0.1 to any port 137 proto udp || { echo "Failed to set firewall rule for Samba UDP 137 from localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 127.0.0.1 to any port 138 proto udp || { echo "Failed to set firewall rule for Samba UDP 138 from localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 127.0.0.1 to any port 139 proto tcp || { echo "Failed to set firewall rule for Samba TCP 139 from localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 127.0.0.1 to any port 445 proto tcp || { echo "Failed to set firewall rule for Samba TCP 445 from localhost" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 10.0.0.0/24 to any port 22 proto tcp || { echo "Failed to set firewall rule for SSH from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 192.168.1.0/24 to any port 22 proto tcp || { echo "Failed to set firewall rule for SSH from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 10.0.0.0/24 to any port 8006 proto tcp || { echo "Failed to set firewall rule for Proxmox UI from 10.0.0.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw allow from 192.168.1.0/24 to any port 8006 proto tcp || { echo "Failed to set firewall rule for Proxmox UI from 192.168.1.0/24" | tee -a "$LOGFILE"; exit 1; }
    ufw status | grep -E "137|138|139|445|22|8006" || { echo "Failed to verify firewall rules" | tee -a "$LOGFILE"; exit 1; }
}

# Prompt for SMB user and password
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
}

# Configure Samba user
configure_samba_user() {
    echo "Configuring Samba user $SMB_USER..." | tee -a "$LOGFILE"
    if ! id "$SMB_USER" > /dev/null 2>&1; then
        useradd -M -s /sbin/nologin "$SMB_USER" || {
            echo "Failed to create Samba user $SMB_USER"
            exit 1
        }
    fi
    echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | smbpasswd -s -a "$SMB_USER" || {
        echo "Failed to set Samba password for $SMB_USER"
        exit 1
    }
    smbpasswd -e "$SMB_USER" || {
        echo "Failed to enable Samba user $SMB_USER"
        exit 1
    }
    echo "Samba user $SMB_USER configured successfully"
}

# Configure Samba server
configure_samba() {
    echo "Configuring Samba server..." | tee -a "$LOGFILE"
    cat << EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server signing = mandatory
   security = user
   map to guest = never
   interfaces = vmbr0 lo
   bind interfaces only = yes

# Samba shares will be configured in phoenix_setup_zfs_datasets.sh
EOF
    testparm -s || { echo "Error: Invalid Samba configuration"; exit 1; }
    systemctl enable --now smbd nmbd || { echo "Failed to enable Samba services"; exit 1; }
}

# Verify Samba services and responsiveness
verify_samba() {
    echo "Verifying Samba services and responsiveness..." | tee -a "$LOGFILE"
    # Check if services are running
    for service in smbd nmbd; do
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
    for port in 137/udp 138/udp 139/tcp 445/tcp; do
        port_num=${port%%/*} # Extract port number (e.g., 137)
        proto=${port##*/}    # Extract protocol (e.g., udp or tcp)
        if [ "$proto" = "udp" ]; then
            if ! ss -uln | grep -q ":$port_num "; then
                echo "Error: Port $port is not listening"
                exit 1
            fi
        else
            if ! ss -tln | grep -q ":$port_num "; then
                echo "Error: Port $port is not listening"
                exit 1
            fi
        fi
        echo "Port $port is listening"
    done

    # Test Samba responsiveness with a temporary share
    echo "Creating temporary Samba share for testing..." | tee -a "$LOGFILE"
    mkdir -p /tmp/samba-test
    chown "$SMB_USER":"$SMB_USER" /tmp/samba-test
    chmod 755 /tmp/samba-test
    cat << EOF >> /etc/samba/smb.conf
[samba-test]
   path = /tmp/samba-test
   writable = yes
   browsable = yes
   valid users = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF
    systemctl restart smbd nmbd || { echo "Failed to restart Samba services"; exit 1; }

    echo "Enter Samba password for user $SMB_USER (input hidden):"
    read -r -s TEST_SMB_PASSWORD
    if [[ -z "$TEST_SMB_PASSWORD" ]]; then
        echo "Error: Test Samba password cannot be empty"
        rm -rf /tmp/samba-test /tmp/samba-test-file
        sed -i '/\[samba-test\]/,/^$/d' /etc/samba/smb.conf
        systemctl restart smbd nmbd
        exit 1
    fi

    echo "Testing Samba share listing..." | tee -a "$LOGFILE"
    smbclient -L //localhost -U "$SMB_USER%$TEST_SMB_PASSWORD" | grep -q samba-test || {
        echo "Error: Failed to list temporary Samba share"
        rm -rf /tmp/samba-test /tmp/samba-test-file
        sed -i '/\[samba-test\]/,/^$/d' /etc/samba/smb.conf
        systemctl restart smbd nmbd
        exit 1
    }
    echo "Temporary Samba share listed successfully"

    echo "Testing Samba file upload..." | tee -a "$LOGFILE"
    echo "test" > /tmp/samba-test-file
    chown "$SMB_USER":"$SMB_USER" /tmp/samba-test-file
    chmod 644 /tmp/samba-test-file
    smbclient "//localhost/samba-test" "$TEST_SMB_PASSWORD" -U "$SMB_USER" -c "put /tmp/samba-test-file testfile" 2>&1 || {
        echo "Error: Failed to upload test file to temporary Samba share"
        rm -rf /tmp/samba-test /tmp/samba-test-file
        sed -i '/\[samba-test\]/,/^$/d' /etc/samba/smb.conf
        systemctl restart smbd nmbd
        exit 1
    }
    echo "Temporary Samba share upload successful"

    # Clean up
    rm -rf /tmp/samba-test /tmp/samba-test-file
    sed -i '/\[samba-test\]/,/^$/d' /etc/samba/smb.conf
    systemctl restart smbd nmbd
    echo "Samba server is responsive"
}

# Main execution
main() {
    check_root
    setup_logging
    prompt_for_subnet
    install_prerequisites
    configure_firewall_samba
    prompt_for_smb_credentials
    configure_samba_user
    configure_samba
    verify_samba
    echo "Samba setup and verification completed successfully at $(date)"
}

main