#!/bin/bash

# proxmox_install_nvidia_driver.sh
# Installs NVIDIA drivers on Proxmox VE
# Version: 1.0.3
# Author: Heads, Grok, Devstral
# Usage: ./proxmox_install_nvidia_driver.sh [--no-reboot]
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Source common functions
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }

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
    echo "blacklist nouveau" >> "$blacklist_file" || { echo "Error: Failed to add nouveau blacklist to $blacklist_file"; exit 1; }
    echo "options nouveau modeset=0" >> "$blacklist_file" || { echo "Error: Failed to add nouveau modeset option to $blacklist_file"; exit 1; }
    echo "[$(date)] Blacklisted nouveau driver in $blacklist_file" >> "$LOGFILE"
  fi
}

# Install kernel headers and check for new kernel
install_pve_headers() {
  local kernel_version=$(uname -r)
  if ! check_package "pve-headers-$kernel_version"; then
    echo "Installing pve-headers for kernel $kernel_version, this may take a while..." | tee -a "$LOGFILE"
    retry_command "apt-get install -y pve-headers-$kernel_version"
    echo "[$(date)] Installed pve-headers for kernel $kernel_version" >> "$LOGFILE"
    
    # Check if a newer kernel is available after installing headers
    local latest_kernel=$(apt list --installed | grep pve-kernel | awk -F/ '{print $1}' | sort -V | tail -n 1)
    if [[ -n "$latest_kernel" && "$latest_kernel" != "pve-kernel-$kernel_version" ]]; then
      echo "Warning: A newer kernel ($latest_kernel) is installed. A reboot is required to use it." | tee -a "$LOGFILE"
      if [[ $NO_REBOOT -eq 0 ]]; then
        read -t 60 -p "Reboot now to use the new kernel? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
        if [[ "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
          echo "Rebooting system to apply new kernel..." | tee -a "$LOGFILE"
          reboot
        else
          echo "Please reboot manually to use the new kernel before continuing." | tee -a "$LOGFILE"
          exit 0
        fi
      else
        echo "Reboot skipped due to --no-reboot flag. Please reboot manually to use the new kernel." | tee -a "$LOGFILE"
        exit 0
      fi
    fi
  else
    echo "Warning: pve-headers for kernel $kernel_version already installed, skipping" | tee -a "$LOGFILE"
  fi
}

# Add NVIDIA CUDA repository
add_nvidia_repo() {
  local distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  local cuda_keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-keyring_1.1-1_all.deb"
  local cuda_keyring_file="/tmp/cuda-keyring.deb"

  if ! check_package cuda-keyring; then
    retry_command "curl -s -L $cuda_keyring_url -o $cuda_keyring_file"
    retry_command "dpkg -i $cuda_keyring_file"
    rm -f "$cuda_keyring_file" || { echo "Warning: Failed to remove temporary file $cuda_keyring_file"; }
    echo "[$(date)] Added NVIDIA CUDA repository" >> "$LOGFILE"
  else
    echo "Warning: cuda-keyring already installed, skipping" | tee -a "$LOGFILE"
  fi
}

# Install NVIDIA drivers and nvtop
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

# Verify NVIDIA driver installation
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

# Update initramfs
update_initramfs() {
  retry_command "update-initramfs -u"
  echo "[$(date)] Updated initramfs" >> "$LOGFILE"
}

# Main execution
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
      echo "Rebooting system..." | tee -a "$LOGFILE"
      reboot
    else
      echo "Please reboot manually to apply changes." | tee -a "$LOGFILE"
    fi
  else
    echo "System update skipped." | tee -a "$LOGFILE"
    read -t 60 -p "Reboot now to apply driver changes? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
    if [[ "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
      echo "Rebooting system..." | tee -a "$LOGFILE"
      reboot
    else
      echo "Please reboot manually to apply changes." | tee -a "$LOGFILE"
    fi
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually to apply changes." | tee -a "$LOGFILE"
fi
echo "[$(date)] Completed proxmox_install_nvidia_driver.sh" >> "$LOGFILE"