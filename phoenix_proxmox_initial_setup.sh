#!/bin/bash

# phoenix_proxmox_initial_setup.sh
# Initializes the Proxmox VE environment with essential configurations, including repositories, system updates,
# timezone, NTP, network settings, and firewall rules for the Phoenix server.
# Version: 1.2.0
# Author: Heads, Grok, Devstral

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
echo "[$TIMESTAMP] Initialized logging for phoenix_proxmox_initial_setup.sh" >> "$LOGFILE"

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
    echo "[$TIMESTAMP] Error: Command failed after $max_attempts attempts: $cmd" >> "$LOGFILE"
    return 1
}

# Set executable permissions on scripts
find /usr/local/bin -type f -name "*.sh" -exec chmod +x {} \;
echo "[$TIMESTAMP] Set executable permissions on scripts in /usr/local/bin" >> "$LOGFILE"

# Verify log file access
if [ ! -w "$LOGFILE" ]; then
    echo "Error: Log file $LOGFILE is not writable" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Verified log file access for $LOGFILE" >> "$LOGFILE"

# Configure log rotation
cat << EOF > /etc/logrotate.d/proxmox_setup
$LOGFILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
echo "[$TIMESTAMP] Configured log rotation for $LOGFILE" >> "$LOGFILE"

# Configure repositories
if [ ! -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    echo "[$TIMESTAMP] Warning: Proxmox VE subscription repository file not found, skipping" >> "$LOGFILE"
else
    mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak
    echo "[$TIMESTAMP] Backed up Proxmox VE subscription repository file" >> "$LOGFILE"
fi

if [ ! -f /etc/apt/sources.list.d/ceph.list ]; then
    echo "[$TIMESTAMP] Warning: Ceph subscription repository file not found, skipping" >> "$LOGFILE"
else
    mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.bak
    echo "[$TIMESTAMP] Backed up Ceph subscription repository file" >> "$LOGFILE"
fi

if ! grep -q "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >> /etc/apt/sources.list
    echo "[$TIMESTAMP] Added Proxmox VE no-subscription repository" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] Warning: Proxmox VE no-subscription repository already enabled, skipping" >> "$LOGFILE"
fi

if ! grep -q "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" >> /etc/apt/sources.list
    echo "[$TIMESTAMP] Added Ceph no-subscription repository" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] Warning: Ceph no-subscription repository already enabled, skipping" >> "$LOGFILE"
fi

# Update and upgrade system
echo "[$TIMESTAMP] Updating and upgrading system (this may take a while)..." >> "$LOGFILE"
retry_command "apt-get update" || { echo "Error: Failed to update package lists" | tee -a "$LOGFILE"; exit 1; }
retry_command "apt-get dist-upgrade -y" || { echo "Error: Failed to upgrade system" | tee -a "$LOGFILE"; exit 1; }
retry_command "proxmox-boot-tool refresh" || { echo "Error: Failed to refresh proxmox-boot-tool" | tee -a "$LOGFILE"; exit 1; }
retry_command "update-initramfs -u" || { echo "Error: Failed to update initramfs" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] System updated, upgraded, and initramfs refreshed" >> "$LOGFILE"

# Install s-tui
echo "[$TIMESTAMP] Installing s-tui..." >> "$LOGFILE"
retry_command "apt-get install -y s-tui" || { echo "Error: Failed to install s-tui" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Installed s-tui" >> "$LOGFILE"

# Install Samba packages
if ! command -v smbd >/dev/null 2>&1; then
    echo "[$TIMESTAMP] Installing Samba..." >> "$LOGFILE"
    retry_command "apt-get install -y samba samba-common-bin smbclient" || { echo "Error: Failed to install Samba" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Installed Samba" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] Samba already installed, skipping installation" >> "$LOGFILE"
fi

# Set timezone
retry_command "timedatectl set-timezone America/New_York" || { echo "Error: Failed to set timezone" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Timezone set to America/New_York" >> "$LOGFILE"

# Configure NTP
echo "[$TIMESTAMP] Configuring NTP with chrony..." >> "$LOGFILE"
retry_command "apt-get install -y chrony" || { echo "Error: Failed to install chrony" | tee -a "$LOGFILE"; exit 1; }
retry_command "systemctl enable --now chrony.service" || { echo "Error: Failed to enable chrony" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] NTP configured with chrony" >> "$LOGFILE"

# Prompt for network configuration with validation
read -p "Enter the hostname for this server (e.g., phoenix) [phoenix]: " HOSTNAME
HOSTNAME=${HOSTNAME:-phoenix}
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid hostname format" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set HOSTNAME to $HOSTNAME" >> "$LOGFILE"

read -p "Enter the network interface (e.g., vmbr0) [vmbr0]: " INTERFACE
INTERFACE=${INTERFACE:-vmbr0}
if [[ ! "$INTERFACE" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Error: Invalid network interface format" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set INTERFACE to $INTERFACE" >> "$LOGFILE"

read -p "Enter the IP address for this server (e.g., 10.0.0.13/24) [10.0.0.13/24]: " IP_ADDRESS
IP_ADDRESS=${IP_ADDRESS:-10.0.0.13/24}
if [[ ! "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "Error: Invalid IP address format" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set IP_ADDRESS to $IP_ADDRESS" >> "$LOGFILE"

read -p "Enter the gateway address (e.g., 10.0.0.1) [10.0.0.1]: " GATEWAY
GATEWAY=${GATEWAY:-10.0.0.1}
if [[ ! "$GATEWAY" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: Invalid gateway address format" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set GATEWAY to $GATEWAY" >> "$LOGFILE"

read -p "Enter the DNS server address (e.g., 8.8.8.8) [8.8.8.8]: " DNS_SERVER
DNS_SERVER=${DNS_SERVER:-8.8.8.8}
if [[ ! "$DNS_SERVER" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: Invalid DNS server address format" | tee -a "$LOGFILE"
    exit 1
fi
echo "[$TIMESTAMP] Set DNS_SERVER to $DNS_SERVER" >> "$LOGFILE"

# Set hostname
retry_command "hostnamectl set-hostname $HOSTNAME" || { echo "Error: Failed to set hostname" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Set hostname to $HOSTNAME" >> "$LOGFILE"

# Configure network
cat << EOF > /etc/network/interfaces.d/50-$INTERFACE.cfg
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    gateway $GATEWAY
    dns-nameservers $DNS_SERVER
EOF
retry_command "systemctl restart networking" || { echo "Error: Failed to restart networking" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Configured static IP for interface $INTERFACE with address $IP_ADDRESS, gateway $GATEWAY, and DNS $DNS_SERVER" >> "$LOGFILE"

# Update /etc/hosts
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    echo "[$TIMESTAMP] Added $HOSTNAME to /etc/hosts" >> "$LOGFILE"
else
    echo "[$TIMESTAMP] Hostname $HOSTNAME already in /etc/hosts, skipping" >> "$LOGFILE"
fi

# Install ufw if not present
if ! command -v ufw >/dev/null 2>&1; then
    echo "[$TIMESTAMP] Installing ufw..." >> "$LOGFILE"
    retry_command "apt-get install -y ufw" || { echo "Error: Failed to install ufw" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Installed ufw" >> "$LOGFILE"
fi

# Configure firewall
echo "[$TIMESTAMP] Configuring firewall rules..." >> "$LOGFILE"
retry_command "ufw allow OpenSSH" || { echo "Error: Failed to allow OpenSSH in firewall" | tee -a "$LOGFILE"; exit 1; }
retry_command "ufw allow 8006/tcp" || { echo "Error: Failed to allow Proxmox UI port in firewall" | tee -a "$LOGFILE"; exit 1; }
retry_command "ufw allow 2049/tcp" || { echo "Error: Failed to allow NFS port in firewall" | tee -a "$LOGFILE"; exit 1; }
retry_command "ufw allow 111/tcp" || { echo "Error: Failed to allow RPC port in firewall" | tee -a "$LOGFILE"; exit 1; }
retry_command "ufw allow Samba" || { echo "Error: Failed to allow Samba in firewall" | tee -a "$LOGFILE"; exit 1; }
retry_command "ufw enable" || { echo "Error: Failed to enable ufw" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Firewall rules configured and enabled" >> "$LOGFILE"

echo "[$TIMESTAMP] Successfully completed phoenix_proxmox_initial_setup.sh" >> "$LOGFILE"
exit 0