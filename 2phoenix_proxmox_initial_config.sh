#!/bin/bash

# phoenix_proxmox_initial_config.sh
# Configures Proxmox VE repositories, sets up logging, installs s-tui, and performs initial system setup
# Version: 1.1.0
# Author: Heads, Grok, Devstral
# Usage: ./phoenix_proxmox_initial_config.sh [--no-reboot]
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

# Set script permissions
set_script_permissions() {
  echo "Setting executable permissions on scripts in /usr/local/bin..." | tee -a "$LOGFILE"
  chmod +x /usr/local/bin/*.sh || { echo "Error: Failed to set permissions on scripts in /usr/local/bin"; exit 1; }
  echo "[$(date)] Set executable permissions on scripts in /usr/local/bin" >> "$LOGFILE"
}

# Configure log rotation
configure_log_rotation() {
  local logrotate_config="/etc/logrotate.d/proxmox_setup"
  echo "Configuring log rotation for $LOGFILE..." | tee -a "$LOGFILE"
  cat > "$logrotate_config" << 'EOF'
/var/log/proxmox_setup.log
{
    weekly
    rotate 4
    compress
    missingok
}
EOF
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create logrotate configuration at $logrotate_config" | tee -a "$LOGFILE"
    exit 1
  fi
  # Test log rotation configuration
  logrotate -f "$logrotate_config" || { echo "Error: Failed to test logrotate configuration"; exit 1; }
  echo "[$(date)] Configured log rotation for $LOGFILE" >> "$LOGFILE"
}

# Verify log file access
verify_log_access() {
  echo "Verifying log file access for $LOGFILE..." | tee -a "$LOGFILE"
  mkdir -p /var/log || { echo "Error: Failed to create /var/log directory"; exit 1; }
  touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE"; exit 1; }
  chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE"; exit 1; }
  echo "Test log entry" >> "$LOGFILE" || { echo "Error: Failed to write test entry to $LOGFILE"; exit 1; }
  if ! cat "$LOGFILE" | grep -q "Test log entry"; then
    echo "Error: Failed to verify log file $LOGFILE" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date)] Verified log file access for $LOGFILE" >> "$LOGFILE"
}


# Disable Proxmox VE production repository
disable_pve_production_repo() {
  echo "Disabling Proxmox VE production repository..." | tee -a "$LOGFILE"
  local pve_repo_file="/etc/apt/sources.list.d/pve-enterprise.list"
  if [[ -f "$pve_repo_file" ]]; then
    sed -i 's/^deb/#deb/' "$pve_repo_file" || { echo "Error: Failed to disable Proxmox VE production repository"; exit 1; }
    echo "[$(date)] Disabled Proxmox VE production repository" >> "$LOGFILE"
  else
    echo "Warning: Proxmox VE production repository file not found, skipping" | tee -a "$LOGFILE"
  fi
}

# Disable Ceph repository
disable_ceph_repo() {
  echo "Disabling Ceph repository..." | tee -a "$LOGFILE"
  local ceph_repo_file="/etc/apt/sources.list.d/ceph.list"
  if [[ -f "$ceph_repo_file" ]]; then
    sed -i 's/^deb/#deb/' "$ceph_repo_file" || { echo "Error: Failed to disable Ceph repository"; exit 1; }
    echo "[$(date)] Disabled Ceph repository" >> "$LOGFILE"
  else
    echo "Warning: Ceph repository file not found, skipping" | tee -a "$LOGFILE"
  fi
}

# Enable Proxmox VE no-subscription repository
enable_pve_no_subscription_repo() {
  echo "Enabling Proxmox VE no-subscription repository..." | tee -a "$LOGFILE"
  local sources_list="/etc/apt/sources.list"
  local no_sub_repo="deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
  if ! grep -q "$no_sub_repo" "$sources_list"; then
    echo "$no_sub_repo" >> "$sources_list" || { echo "Error: Failed to add Proxmox VE no-subscription repository"; exit 1; }
    echo "[$(date)] Added Proxmox VE no-subscription repository" >> "$LOGFILE"
  else
    echo "Warning: Proxmox VE no-subscription repository already enabled, skipping" | tee -a "$LOGFILE"
  fi
}

# Update and upgrade system
update_system() {
  echo "Updating and upgrading system (this may take a while)..." | tee -a "$LOGFILE"
  retry_command "apt-get update"
  retry_command "apt-get upgrade -y"
  retry_command "proxmox-boot-tool refresh"
  retry_command "update-initramfs -u"
  echo "[$(date)] System updated, upgraded, and initramfs refreshed" >> "$LOGFILE"
}

# Install s-tui
install_s_tui() {
  echo "Installing s-tui..." | tee -a "$LOGFILE"
  if ! check_package "s-tui"; then
    retry_command "apt-get install -y s-tui"
    echo "[$(date)] Installed s-tui" >> "$LOGFILE"
  fi
}

# Main execution
check_root
set_script_permissions
configure_log_rotation
verify_log_access
disable_pve_production_repo
disable_ceph_repo
enable_pve_no_subscription_repo
update_system
install_s_tui

echo "Proxmox VE initial configuration complete."
echo "- Configured logging and log rotation."
echo "- Installed s-tui."
echo "- Disabled production and Ceph repositories."
echo "- Enabled no-subscription repository."
echo "- Updated system."
if [[ $NO_REBOOT -eq 0 ]]; then
  read -t 60 -p "Reboot now? (y/n) [Timeout in 60s]: " REBOOT_CONFIRMATION
  if [[ -z "$REBOOT_CONFIRMATION" || "$REBOOT_CONFIRMATION" == "y" || "$REBOOT_CONFIRMATION" == "Y" ]]; then
    echo "Rebooting system..."
    reboot
  else
    echo "Please reboot manually to apply changes."
  fi
else
  echo "Reboot skipped due to --no-reboot flag. Please reboot manually."
fi
echo "[$(date)] Completed phoenix_proxmox_initial_config.sh" >> "$LOGFILE"