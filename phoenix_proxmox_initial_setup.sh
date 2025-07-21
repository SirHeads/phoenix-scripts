#!/bin/bash

# phoenix_proxmox_initial_setup.sh
# Initial setup for Proxmox VE
# Version: 1.0.4
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

# Update system packages and configure NTP
update_system() {
  retry_command "apt-get update && apt-get upgrade -y"

  setup_timezone
  configure_ntp

  echo "[$(date)] System updated and NTP configured" >> "$LOGFILE"
}

setup_timezone() {
  read -p "Enter timezone (e.g., Europe/Berlin): " TIMEZONE
  if timedatectl list-timezones | grep -q "^$TIMEZONE$"; then
    retry_command "timedatectl set-timezone $TIMEZONE"
    echo "[$(date)] Timezone set to $TIMEZONE" >> "$LOGFILE"
  else
    echo "Error: Invalid timezone specified." | tee -a "$LOGFILE"
    exit 1
  fi
}

configure_ntp() {
  retry_command "apt-get install -y chrony"
  systemctl enable --now chrony.service

  if ! systemctl is-active --quiet chrony.service; then
    echo "Error: Failed to start chrony service." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] NTP configured with Chrony" >> "$LOGFILE"
}

disable_unnecessary_services() {
  retry_command "systemctl disable --now apparmor.service"
  retry_command "systemctl disable --now pve-cluster.service"

  if ! systemctl is-enabled --quiet apparmor.service && ! systemctl is-enabled --quiet pve-cluster.service; then
    echo "[$(date)] Unnecessary services disabled" >> "$LOGFILE"
  else
    echo "Warning: Failed to disable unnecessary services." | tee -a "$LOGFILE"
  fi
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

    # Validate IP address format
    if ! [[ "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
      echo "Error: Invalid IP address format: $IP_ADDRESS" | tee -a "$LOGFILE"
      exit 1
    fi

    if ! ip addr show "$INTERFACE" > /dev/null; then
      echo "Error: Interface $INTERFACE does not exist." | tee -a "$LOGFILE"
      exit 1
    fi

    cat << EOF > "/etc/network/interfaces.d/50-$INTERFACE.cfg"
auto $INTERFACE
iface $INTERFACE inet static
address $IP_ADDRESS
EOF

    echo "[$(date)] Configured static IP for interface $INTERFACE with address $IP_ADDRESS" >> "$LOGFILE"
  }
}

update_hosts_file() {
  if ! grep -q "^127.0.1.1.*$HOSTNAME" /etc/hosts; then
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts || { echo "Error: Failed to update /etc/hosts" | tee -a "$LOGFILE"; exit 1; }
  fi

  echo "[$(date)] Updated /etc/hosts with $HOSTNAME" >> "$LOGFILE"
}

# Setup firewall rules
setup_firewall() {
  # Allow Proxmox VE services through the firewall
  retry_command "ufw allow OpenSSH"

  # Check for Samba installation before applying firewall rule
  if check_package samba; then
    retry_command "ufw allow Samba"
  fi

  # Check for NFS installation before applying firewall rule
  if check_package nfs-kernel-server; then
    retry_command "ufw allow from $PROXMOX_NFS_SERVER to any port nfs"
  fi

  echo "[$(date)] Configured firewall rules" >> "$LOGFILE"
}

# Main execution using common functions
main() {
  check_root
  setup_logging
  update_system
  configure_network
  setup_firewall

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