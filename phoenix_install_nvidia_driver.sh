#!/bin/bash

# phoenix_install_nvidia_driver.sh
# Installs NVIDIA drivers on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_install_nvidia_driver.sh [--no-reboot]
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

# Blacklist nouveau driver
blacklist_nouveau() {
  if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist.conf; then
    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to blacklist nouveau"; exit 1; }
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist.conf || { echo "Error: Failed to add options for nouveau"; exit 1; }
  fi
}

# Install Proxmox VE headers using common functions
install_pve_headers() {
  if ! check_package pve-headers; then
    retry_command "apt-get update && apt-get install -y pve-headers"
    echo "[$(date)] Installed pve-headers" >> "$LOGFILE"
  fi
}

# Add NVIDIA repository using common functions
add_nvidia_repo() {
  local repo_line="deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(lsb_release -sr | tr -d .)/x86_64/ /"
  if ! grep -q nvidia /etc/apt/sources.list.d/nvidia.list; then
    echo "$repo_line" > /etc/apt/sources.list.d/nvidia.list || { echo "Error: Failed to add NVIDIA repository"; exit 1; }
    retry_command "apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(lsb_release -sr | tr -d .)/x86_64/7fa2af80.pub"
    retry_command "apt-get update"
  fi
}

# Install NVIDIA drivers and nvtop using common functions
install_nvidia_driver() {
  retry_command "apt-get update"
  if ! check_package nvidia-driver-assistant; then
    echo "Installing nvidia-driver-assistant and nvtop, this may take a while..." | tee -a "$LOGFILE"
    retry_command "apt-get install -y nvidia-driver-assistant nvtop"
    echo "[$(date)] Installed nvidia-driver-assistant and nvtop" >> "$LOGFILE"
  fi
  retry_command "nvidia-driver-assistant"
  if ! check_package nvidia-open; then
    retry_command "apt-get install -Vy nvidia-open"
    echo "[$(date)] Installed nvidia-open driver" >> "$LOGFILE"
  fi
}

# Verify NVIDIA driver installation using common functions
verify_nvidia_installation() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local nvidia_smi_output
    nvidia_smi_output=$(nvidia-smi 2>&1)
    if [[ $? -eq 0 ]]; then
      echo "[$(date)] NVIDIA driver verification successful" >> "$LOGFILE"
      echo "$nvidia_smi_output" >> "$LOGFILE"
    else
      echo "Error: nvidia-smi failed: $nvidia_smi_output" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    echo "Error: nvidia-smi command not found after driver installation" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Update initramfs using common functions
update_initramfs() {
  retry_command "update-initramfs -u"
  echo "[$(date)] Updated initramfs" >> "$LOGFILE"
}

# Main execution
main() {
  check_root
  blacklist_nouveau
  install_pve_headers
  add_nvidia_repo
  install_nvidia_driver
  verify_nvidia_installation
  update_initramfs

  echo "NVIDIA driver installation and verification complete."
  if [[ $NO_REBOOT -eq 0 ]]; then
    read -t 60 -p "NVIDIA driver installation verified. Would you like to update the system to the latest version and ensure driver compatibility with the latest kernel? This will update packages, install kernel headers, rebuild the driver, and reboot (y/n) [Timeout in 60s]: " UPDATE_CONFIRMATION
    if [[ "$UPDATE_CONFIRMATION" == "y" || "$UPDATE_CONFIRMATION" == "Y" ]]; then
      echo "Updating system and ensuring driver compatibility..." | tee -a "$LOGFILE"
      retry_command "apt-get update"
      retry_command "apt-get upgrade -y"
      retry_command "apt-get install -y pve-headers"
      retry_command "dkms autoinstall"
      echo "[$(date)] System updated, headers installed, and driver rebuilt" >> "$LOGFILE"

      read -t 60 -p "Reboot now to apply changes? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
      if [[ "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
        echo "Rebooting system..."
        reboot
      else
        echo "Please reboot manually to apply changes."
      fi
    else
      echo "Skipping system update and kernel compatibility check. Please ensure the NVIDIA driver is compatible with your current kernel version."
    fi
  else
    echo "Reboot skipped due to --no-reboot flag. Please reboot manually."
  fi

  echo "[$(date)] Completed proxmox_install_nvidia_driver.sh" >> "$LOGFILE"
}

main