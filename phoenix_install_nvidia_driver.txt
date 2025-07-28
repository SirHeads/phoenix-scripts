#!/bin/bash

# phoenix_install_nvidia_driver.sh
# Installs NVIDIA drivers on Proxmox VE
# Version: 1.0.9
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_install_nvidia_driver.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }

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

# Blacklist Nouveau driver
blacklist_nouveau() {
  local blacklist_file="/etc/modprobe.d/blacklist.conf"
  if [[ -f "$blacklist_file" ]] && grep -q "blacklist nouveau" "$blacklist_file"; then
    echo "Warning: Nouveau already blacklisted, skipping" | tee -a "$LOGFILE"
  else
    echo "blacklist nouveau" >> "$blacklist_file" || { echo "Error: Failed to add nouveau blacklist to $blacklist_file" | tee -a "$LOGFILE"; exit 1; }
    echo "options nouveau modeset=0" >> "$blacklist_file" || { echo "Error: Failed to add nouveau modeset option to $blacklist_file" | tee -a "$LOGFILE"; exit 1; }
    echo "[$(date)] Blacklisted nouveau driver in $blacklist_file" >> "$LOGFILE"
    return 0
  fi
  return 1
}

# Install kernel headers and check for new kernel
install_pve_headers() {
  local headers_installed=0
  local kernel_updated=0
  local current_kernel=$(uname -r)
  local headers_pkg="proxmox-headers-$current_kernel"

  echo "[$TIMESTAMP] Checking Proxmox VE kernel headers..." >> "$LOGFILE"

  # Check if headers for the current kernel are installed
  if dpkg -l | grep -q "$headers_pkg"; then
    echo "[$TIMESTAMP] Kernel headers for $current_kernel already installed" >> "$LOGFILE"
  else
    retry_command "apt-get install -y $headers_pkg" || { echo "Error: Failed to install kernel headers for $current_kernel" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Installed kernel headers for $current_kernel" >> "$LOGFILE"
    headers_installed=1
  fi

  # Install generic pve-headers for future kernel updates if not already installed
  if ! dpkg -l | grep -q "proxmox-default-headers"; then
    retry_command "apt-get install -y proxmox-default-headers pve-headers" || { echo "Error: Failed to install generic pve-headers" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Installed generic pve-headers" >> "$LOGFILE"
    headers_installed=1
  else
    echo "[$TIMESTAMP] Generic pve-headers already installed, skipping" >> "$LOGFILE"
  fi

  # Check for newer kernel
  local installed_kernel=$(dpkg -l | grep pve-kernel | grep -o 'pve-kernel-[0-9.-]\+[-pve0-9]*' | sort -V | tail -n 1 | sed 's/pve-kernel-//')
  if [ -n "$installed_kernel" ] && [ "$installed_kernel" != "$current_kernel" ]; then
    echo "[$TIMESTAMP] Newer kernel ($installed_kernel) detected" >> "$LOGFILE"
    kernel_updated=1
  fi

  # Return whether an initramfs update is needed
  if [[ $headers_installed -eq 1 || $kernel_updated -eq 1 ]]; then
    return 0
  else
    return 1
  fi
}

# Check for NVIDIA GPU presence
check_nvidia_gpu() {
  if ! lspci | grep -i nvidia >/dev/null 2>&1; then
    echo "Error: No NVIDIA GPU found on this system." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] NVIDIA GPU detected" >> "$LOGFILE"
}

# Check Proxmox VE version compatibility
check_proxmox_version() {
  if ! command -v pveversion >/dev/null 2>&1; then
    echo "Error: pveversion command not found. Ensure this script is running on a Proxmox VE system." | tee -a "$LOGFILE"
    exit 1
  fi
  local proxmox_version=$(pveversion | cut -d'/' -f2 | cut -d'-' -f1)
  if [[ ! "$proxmox_version" =~ ^8\..* ]]; then
    echo "Error: This script is designed for Proxmox VE 8.x. Found Proxmox VE version: $proxmox_version" | tee -a "$LOGFILE"
    exit 1
  fi
  local debian_version=$(cat /etc/debian_version 2>/dev/null || echo "unknown")
  if [[ ! "$debian_version" =~ ^12\..* ]]; then
    echo "Error: This script is designed for Debian 12. Found Debian version: $debian_version" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Verified Proxmox VE version: $proxmox_version (Debian $debian_version)" >> "$LOGFILE"
}

# Add NVIDIA repository
add_nvidia_repo() {
  local repo_line="deb http://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /"
  if ! grep -q "$repo_line" /etc/apt/sources.list.d/nvidia.list 2>/dev/null; then
    echo "$repo_line" > /etc/apt/sources.list.d/nvidia.list || { echo "Error: Failed to add NVIDIA repository" | tee -a "$LOGFILE"; exit 1; }
    retry_command "apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub" || {
      echo "Error: Failed to download and install NVIDIA key" | tee -a "$LOGFILE"
      exit 1
    }
    retry_command "apt-get update" || {
      echo "Error: Failed to update package lists after adding NVIDIA repository" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$(date)] Added NVIDIA repository and key" >> "$LOGFILE"
    return 0
  else
    echo "[$(date)] NVIDIA repository already configured, skipping" >> "$LOGFILE"
    return 1
  fi
}

# Install NVIDIA driver and tools
install_nvidia_driver() {
  local driver_installed=0
  echo "[$TIMESTAMP] Checking NVIDIA driver and tools..." >> "$LOGFILE"
  if ! dpkg -l | grep -q "nvidia-open-575.57.08"; then
    retry_command "apt-get install -y nvtop nvidia-open-575.57.08" || {
      echo "Error: Failed to install NVIDIA driver and tools" | tee -a "$LOGFILE"
      exit 1
    }
    echo "[$TIMESTAMP] Installed NVIDIA driver and tools" >> "$LOGFILE"
    driver_installed=1
  else
    echo "[$TIMESTAMP] NVIDIA driver and tools already installed, skipping" >> "$LOGFILE"
  fi

  # Rebuild NVIDIA DKMS module for the current kernel if driver was installed
  if [[ $driver_installed -eq 1 ]]; then
    local current_kernel=$(uname -r)
    echo "[$TIMESTAMP] Rebuilding NVIDIA DKMS module for kernel $current_kernel..." >> "$LOGFILE"
    retry_command "dkms autoinstall -k $current_kernel" || { echo "Error: Failed to rebuild NVIDIA DKMS module for $current_kernel" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Successfully rebuilt NVIDIA DKMS module" >> "$LOGFILE"
  fi

  return $driver_installed
}

# Verify NVIDIA installation
verify_nvidia_installation() {
  if ! lsmod | grep -q "^nvidia"; then
    echo "Error: NVIDIA kernel module is not loaded." | tee -a "$LOGFILE"
    exit 1
  fi
  if ! nvidia-smi >/dev/null 2>&1; then
    echo "Error: Failed to run nvidia-smi. Driver installation may be incomplete or incorrect." | tee -a "$LOGFILE"
    exit 1
  fi
  local nvidia_smi_output=$(nvidia-smi)
  echo "[$(date)] NVIDIA driver verification successful" >> "$LOGFILE"
  echo "$nvidia_smi_output" >> "$LOGFILE"
}

# Update initramfs
update_initramfs() {
  retry_command "update-initramfs -u" || {
    echo "Error: Failed to update initramfs" | tee -a "$LOGFILE"
    exit 1
  }
  echo "[$(date)] Updated initramfs" >> "$LOGFILE"
  if [[ $NO_REBOOT -eq 0 ]]; then
    echo "[$(date)] Forcing reboot to apply NVIDIA driver changes in 10 seconds. Press Ctrl+C to cancel." | tee -a "$LOGFILE"
    sleep 10
    reboot
  else
    echo "[$(date)] Reboot skipped due to --no-reboot flag. Please reboot manually to apply NVIDIA driver changes." | tee -a "$LOGFILE"
  fi
}

# Ensure kernel compatibility
ensure_kernel_compatibility() {
  if [[ $NO_REBOOT -eq 0 ]]; then
    read -t 60 -p "Update system to ensure driver compatibility with the latest kernel? (y/n) [Timeout in 60s]: " UPDATE_CONFIRMATION
    if [[ "$UPDATE_CONFIRMATION" == "y" || "$UPDATE_CONFIRMATION" == "Y" ]]; then
      echo "Updating system and ensuring driver compatibility..." | tee -a "$LOGFILE"
      retry_command "apt-get update" || {
        echo "Error: Failed to update package lists" | tee -a "$LOGFILE"
        exit 1
      }
      retry_command "apt-get upgrade -y" || {
        echo "Error: Failed to upgrade system packages" | tee -a "$LOGFILE"
        exit 1
      }
      retry_command "apt-get install -y pve-headers" || {
        echo "Error: Failed to install pve-headers" | tee -a "$LOGFILE"
        exit 1
      }
      retry_command "dkms autoinstall" || {
        echo "Error: Failed to rebuild NVIDIA driver with DKMS" | tee -a "$LOGFILE"
        exit 1
      }
      echo "[$(date)] System updated, headers installed, and driver rebuilt" >> "$LOGFILE"
    else
      echo "Skipping system update for kernel compatibility." | tee -a "$LOGFILE"
    fi
  else
    echo "Warning: Using --no-reboot may cause NVIDIA driver issues if the kernel version is not compatible. A manual reboot with kernel updates is recommended." | tee -a "$LOGFILE"
  fi
}

# Main execution
main() {
  setup_logging
  check_root
  check_proxmox_version
  check_nvidia_gpu

  # Check if NVIDIA driver is already installed and functional
  if lsmod | grep -q "^nvidia" && nvidia-smi >/dev/null 2>&1; then
    echo "[$(date)] NVIDIA driver is already installed and functional, skipping redundant steps" >> "$LOGFILE"
    verify_nvidia_installation
    ensure_kernel_compatibility
    echo "[$(date)] Completed NVIDIA driver installation check" >> "$LOGFILE"
    exit 0
  fi

  local need_initramfs=0
  blacklist_nouveau && need_initramfs=1
  install_pve_headers && need_initramfs=1
  add_nvidia_repo && need_initramfs=1
  install_nvidia_driver && need_initramfs=1
  if [[ $need_initramfs -eq 1 ]]; then
    update_initramfs
  else
    echo "[$(date)] No changes to drivers, headers, or kernel, skipping initramfs update and reboot" >> "$LOGFILE"
  fi
  verify_nvidia_installation
  ensure_kernel_compatibility
}

main
echo "[$(date)] Completed NVIDIA driver installation" >> "$LOGFILE"
exit 0