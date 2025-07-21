#!/bin/bash

# phoenix_proxmox_initial_setup.sh
# Initial setup for Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_proxmox_initial_setup.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }
load_config

# Parse command-line arguments
NO_REBOOT=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-reboot)
      NO_REBOOT=1
      shift
      ;;
    *)
      echo "Error: Unknown option $1" | tee -a "$LOGFILE"
      exit 1
      ;;
  esac
done

# Ensure script runs as root using common function
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Update Proxmox VE system and install required packages using common functions
update_system() {
  retry_command "apt-get update && apt-get upgrade -y"
  if ! check_package ntp; then
    retry_command "apt-get install -y ntp"
  fi
  echo "[$(date)] System updated and NTP installed" >> "$LOGFILE"

  # Set timezone using common function
  setup_timezone() {
    if [[ -z $(timedatectl show --property=Timezone | cut -d '=' -f2) ]]; then
      read -p "Enter your desired time zone (e.g., Europe/Berlin): " TIMEZONE
      retry_command "timedatectl set-timezone $TIMEZONE"
      echo "[$(date)] Timezone set to $TIMEZONE" >> "$LOGFILE"
    fi
  }

  setup_timezone

  # Configure NTP using common function
  configure_ntp() {
    if ! grep -q "^server [0-9]" /etc/ntp.conf; then
      echo "server 0.pool.ntp.org iburst" >> /etc/ntp.conf || { echo "Error: Failed to configure NTP"; exit 1; }
      systemctl restart ntp || { echo "Error: Failed to restart NTP service"; exit 1; }
    fi
    echo "[$(date)] Configured NTP server in /etc/ntp.conf" >> "$LOGFILE"
  }

  configure_ntp

  # Disable unnecessary services using common function
  disable_unnecessary_services() {
    if systemctl is-enabled rsyslog >/dev/null; then
      retry_command "systemctl stop rsyslog && systemctl disable rsyslog"
      echo "[$(date)] Disabled and stopped rsyslog service" >> "$LOGFILE"
    fi

    if systemctl is-active rsyslog >/dev/null; then
      retry_command "systemctl mask rsyslog"
      echo "[$(date)] Masked rsyslog service to prevent accidental enabling" >> "$LOGFILE"
    fi
  }

  disable_unnecessary_services
}

# Configure network settings using common function
configure_network() {
  read -p "Enter the hostname for this server (e.g., proxmox1): " HOSTNAME
  if [[ -z "$HOSTNAME" ]]; then
    echo "Error: Hostname cannot be empty." | tee -a "$LOGFILE"
    exit 1
  fi

  retry_command "hostnamectl set-hostname $HOSTNAME"
  echo "[$(date)] Set hostname to $HOSTNAME" >> "$LOGFILE"

  # Configure static IP if needed using common function
  configure_static_ip() {
    read -p "Enter the network interface (e.g., ens18): " INTERFACE
    read -p "Enter the IP address for this server (e.g., 192.168.0.2/24): " IP_ADDRESS
    if ! ip addr show "$INTERFACE" > /dev/null; then
      echo "Error: Interface $INTERFACE does not exist." | tee -a "$LOGFILE"
      exit 1
    fi

    cat << EOF > "/etc/network/interfaces.d/50-$INTERFACE.cfg"
auto $INTERFACE
iface $INTERFACE inet static
address $IP_ADDRESS
EOF

    retry_command "systemctl restart networking"
    echo "[$(date)] Configured static IP for interface $INTERFACE with address $IP_ADDRESS" >> "$LOGFILE"
  }

  configure_static_ip

  # Update /etc/hosts file using common function
  update_hosts_file() {
    if ! grep -q "^127.0.1.1.*$HOSTNAME" /etc/hosts; then
      echo "127.0.1.1 $HOSTNAME" >> /etc/hosts || { echo "Error: Failed to update /etc/hosts"; exit 1; }
    fi
    echo "[$(date)] Updated /etc/hosts with $HOSTNAME" >> "$LOGFILE"
  }

  update_hosts_file

  # Set up firewall rules using common function
  setup_firewall() {
    if ! ufw status | grep -q "Status: active"; then
      retry_command "ufw allow ssh && ufw enable"
      echo "[$(date)] Enabled UFW and allowed SSH traffic" >> "$LOGFILE"
    fi

    # Allow Proxmox VE services using common function
    for service in 80/tcp 443/tcp 5900:6100/tcp; do
      set_firewall_rule "allow $service"
    done
    echo "[$(date)] Allowed Proxmox VE services through UFW" >> "$LOGFILE"

    # Allow NFS if needed using common function
    if [[ -n "${PROXMOX_NFS_SERVER}" ]]; then
      set_firewall_rule "allow from ${PROXMOX_NFS_SERVER}"
      echo "[$(date)] Allowed NFS server IP ${PROXMOX_NFS_SERVER} through UFW" >> "$LOGFILE"
    fi

    # Allow Samba if needed using common function
    if [[ -n "${SMB_USER}" ]]; then
      set_firewall_rule "allow samba"
      echo "[$(date)] Allowed Samba traffic through UFW" >> "$LOGFILE"
    fi
  }

  setup_firewall
}

# Main execution using common functions
main() {
  check_root
  update_system
  configure_network

  # Reboot system if not skipped
  if [[ $NO_REBOOT -eq 0 ]]; then
    read -t 60 -p "Reboot now to apply changes? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
    if [[ "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
      echo "[$(date)] Rebooting system to apply changes." >> "$LOGFILE"
      reboot
    else
      echo "[$(date)] Skipping reboot. Please reboot manually to apply all changes." >> "$LOGFILE"
    fi
  else
    echo "[$(date)] Skipped reboot due to --no-reboot flag." >> "$LOGFILE"
  fi

  echo "[$(date)] Completed initial Proxmox VE setup" >> "$LOGFILE"
}

main