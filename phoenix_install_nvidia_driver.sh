#!/bin/bash

# phoenix_install_nvidia_driver.sh
# Installs NVIDIA drivers on Proxmox VE
# Version: 1.0.4
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

# Initialize logging
setup_logging

# Check for NVIDIA GPU presence using lspci
check_nvidia_gpu() {
  if ! lspci | grep -i nvidia > /dev/null; then
    echo "Error: No NVIDIA GPU found on this system." | tee -a "$LOGFILE"
    exit 1
  fi
}

# Check Proxmox VE version compatibility
check_proxmox_version() {
  if ! command -v pveversion >/dev/null 2>&1; then
    echo "Error: pveversion command not found. Ensure this script is running on a Proxmox VE system." | tee -a "$LOGFILE"
    exit 1
  fi

  # Check Debian version (Proxmox VE 8.x is based on Debian 12)
  if [[ -f /etc/debian_version ]]; then
    DEBIAN_VERSION=$(cat /etc/debian_version)
    if [[ ! "$DEBIAN_VERSION" =~ ^12\..* ]]; then
      echo "Error: This script is designed for Proxmox VE based on Debian 12. Found Debian version: $DEBIAN_VERSION" | tee -a "$LOGFILE"
      exit 1
    fi
  else
    echo "Error: Cannot determine Debian version. /etc/debian_version not found." | tee -a "$LOGFILE"
    exit 1
  fi

  # Check Proxmox VE version
  PROXMOX_VERSION=$(pveversion | cut -d'/' -f2 | cut -d'-' -f1)
  if [[ ! "$PROXMOX_VERSION" =~ ^8\..* ]]; then
    echo "Error: This script is designed for Proxmox VE 8.x. Found Proxmox VE version: $PROXMOX_VERSION" | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] Verified Proxmox VE version: $PROXMOX_VERSION (Debian $DEBIAN_VERSION)" >> "$LOGFILE"
}

# Add the NVIDIA repository using a static URL for Debian 12-based Proxmox VE
add_nvidia_repo() {
  local repo_line="deb http://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /"
  if ! grep -q nvidia /etc/apt/sources.list.d/nvidia.list; then
    echo "$repo_line" > /etc/apt/sources.list.d/nvidia.list || { echo "Error: Failed to add NVIDIA repository" | tee -a "$LOGFILE"; exit 1; }
    retry_command "apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/7fa2af80.pub"
    retry_command "apt-get update"
  fi
  echo "[$(date)] Added NVIDIA repository" >> "$LOGFILE"
}

# Install the NVIDIA driver and related packages
install_nvidia_driver() {
  retry_command "apt-get update"

  if ! check_package nvidia-driver; then
    echo "Installing NVIDIA driver and tools, this may take a while..." | tee -a "$LOGFILE"
    retry_command "apt-get install -y nvidia-driver nvtop"
    echo "[$(date)] Installed NVIDIA driver and tools" >> "$LOGFILE"
  fi

  if ! check_package nvidia-open; then
    retry_command "apt-get install -y nvidia-open"
    echo "[$(date)] Installed NVIDIA OpenGL driver" >> "$LOGFILE"
  fi
}

# Verify the NVIDIA installation by checking module loading and nvidia-smi command
verify_nvidia_installation() {
  if ! lsmod | grep -q "^nvidia"; then
    echo "Error: NVIDIA kernel module is not loaded." | tee -a "$LOGFILE"
    exit 1
  fi

  if ! nvidia-smi; then
    echo "Error: Failed to run nvidia-smi. Driver installation may be incomplete or incorrect." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] NVIDIA driver installation verified" >> "$LOGFILE"
}

# Ensure kernel compatibility by updating system packages and headers (unless --no-reboot is specified)
ensure_kernel_compatibility() {
  if [[ $NO_REBOOT -eq 0 ]]; then
    read -t 60 -p "Update system to ensure driver compatibility with the latest kernel? This will update packages, install kernel headers, rebuild the driver, and reboot (y/n) [Timeout in 60s]: " UPDATE_CONFIRMATION

    if [[ "$UPDATE_CONFIRMATION" == "y" || "$UPDATE_CONFIRMATION" == "Y" ]]; then
      echo "Updating system and ensuring driver compatibility..." | tee -a "$LOGFILE"
      retry_command "apt-get update"
      retry_command "apt-get upgrade -y"
      retry_command "apt-get install -y pve-headers"
      retry_command "dkms autoinstall"

      if ! dkms status; then
        echo "Error: DKMS failed to rebuild the NVIDIA driver." | tee -a "$LOGFILE"
        exit 1
      fi

      echo "[$(date)] System updated, headers installed, and driver rebuilt" >> "$LOGFILE"
    else
      echo "Skipping system update for kernel compatibility." | tee -a "$LOGFILE"
    fi
  else
    echo "Warning: Using --no-reboot may cause NVIDIA driver issues if the kernel version is not compatible. A manual reboot with kernel updates is recommended." | tee -a "$LOGFILE"
  fi
}

# Main execution using common functions
main() {
  check_root
  setup_logging
  check_proxmox_version
  check_nvidia_gpu
  add_nvidia_repo
  install_nvidia_driver
  verify_nvidia_installation

  # Ensure kernel compatibility if not skipped by --no-reboot flag
  ensure_kernel_compatibility
}

main