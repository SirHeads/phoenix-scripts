#!/bin/bash

# master_setup.sh
# Orchestrates the execution of all Proxmox VE setup scripts
# Version: 1.0.9
# Author: Heads, Grok, Devstral

# Source common functions and configuration variables
source /usr/local/bin/common.sh || { echo "Error: Failed to source common.sh"; exit 1; }
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh"; exit 1; }

# State file to track completed scripts
STATE_FILE="/var/log/proxmox_setup_state"

# Ensure script runs as root using common function
check_root

# Initialize state file if it doesn't exist
init_state_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    touch "$STATE_FILE" || { echo "Error: Failed to create $STATE_FILE"; exit 1; }
    chmod 644 "$STATE_FILE"
    echo "[$(date)] Initialized state file: $STATE_FILE" >> "$LOGFILE"
  fi
}

# Check if a script has already been completed
is_script_completed() {
  local script="$1"
  grep -Fx "$script" "$STATE_FILE" >/dev/null
}

# Mark a script as completed
mark_script_completed() {
  local script="$1"
  echo "$script" >> "$STATE_FILE" || { echo "Error: Failed to update $STATE_FILE"; exit 1; }
  echo "[$(date)] Marked $script as completed in $STATE_FILE" >> "$LOGFILE"
}

# Prompt for admin credentials if not set in environment
prompt_for_credentials() {
  if [[ -z "$ADMIN_USERNAME" ]]; then
    read -p "Enter admin username for phoenix_create_admin_user.sh [adminuser]: " ADMIN_USERNAME
    ADMIN_USERNAME=${ADMIN_USERNAME:-adminuser}
  fi
  if [[ -z "$ADMIN_PASSWORD" ]]; then
    read -s -p "Enter password for admin user (min 8 chars, 1 special char): " ADMIN_PASSWORD
    echo
    if [[ ! "$ADMIN_PASSWORD" =~ [[:punct:]] || ${#ADMIN_PASSWORD} -lt 8 ]]; then
      echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
      exit 1
    fi
  fi
}

# Check for NVIDIA GPU presence
check_nvidia_gpu() {
  if lspci | grep -i nvidia >/dev/null 2>&1; then
    return 0
  else
    echo "[$(date)] No NVIDIA GPU detected, skipping phoenix_install_nvidia_driver.sh" | tee -a "$LOGFILE"
    return 1
  fi
}

# Setup systemd service for automatic resumption after reboot
setup_resume_service() {
  read -p "Set up automatic resumption of setup after reboot? (y/n): " RESUME_CONFIRMATION
  if [[ "$RESUME_CONFIRMATION" == "y" || "$RESUME_CONFIRMATION" == "Y" ]]; then
    cat << EOF > /etc/systemd/system/proxmox-setup-resume.service
[Unit]
Description=Resume Proxmox VE Setup After Reboot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/master_setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable proxmox-setup-resume.service
    echo "[$(date)] Enabled systemd service for automatic setup resumption" | tee -a "$LOGFILE"
  fi
}

# Clean up all automation mechanisms to prevent future runs
cleanup_automation() {
  # Disable and remove systemd service
  systemctl disable proxmox-setup-resume.service 2>/dev/null
  rm -f /etc/systemd/system/proxmox-setup-resume.service
  echo "[$(date)] Removed systemd service proxmox-setup-resume.service" | tee -a "$LOGFILE"

  # Check for and remove any related cron jobs
  if crontab -l 2>/dev/null | grep -q "master_setup.sh"; then
    crontab -l | grep -v "master_setup.sh" | crontab -
    echo "[$(date)] Removed any cron jobs related to master_setup.sh" | tee -a "$LOGFILE"
  fi

  # Remove state file
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    echo "[$(date)] Removed state file: $STATE_FILE" | tee -a "$LOGFILE"
  fi

  # Verify no residual automation mechanisms
  if systemctl list-units --full | grep -q "proxmox-setup-resume" || crontab -l 2>/dev/null | grep -q "master_setup.sh"; then
    echo "Error: Residual automation mechanisms detected. Please manually remove them." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date)] All automatic execution mechanisms have been removed" | tee -a "$LOGFILE"
}

# List of scripts to execute
scripts=(
  "/usr/local/bin/phoenix_proxmox_initial_setup.sh"
  "/usr/local/bin/common.sh"
  "/usr/local/bin/phoenix_config.sh"
  "/usr/local/bin/phoenix_install_nvidia_driver.sh --no-reboot"
  "/usr/local/bin/phoenix_create_admin_user.sh -u $ADMIN_USERNAME -p '$ADMIN_PASSWORD'"
  "if ! dpkg-query -W zfsutils-linux > /dev/null; then apt-get update && apt-get install -y zfsutils-linux; fi"
  "/usr/local/bin/phoenix_setup_zfs_pools.sh -d sdb"
  "/usr/local/bin/phoenix_setup_zfs_datasets.sh -p rpool -d $(IFS=','; echo "${ZFS_DATASET_LIST[*]}")"
  "/usr/local/bin/phoenix_setup_nfs.sh --no-reboot"
  "/usr/local/bin/phoenix_setup_samba.sh"
)

# Execute each script in order with user feedback and state tracking
init_state_file
prompt_for_credentials
setup_resume_service
for script in "${scripts[@]}"; do
  # Check if the script file exists (skip for inline commands like zfsutils-linux check)
  if [[ "$script" != *"dpkg-query"* ]]; then
    script_file=$(echo "$script" | awk '{print $1}')
    if [[ ! -f "$script_file" ]]; then
      echo "Error: Script $script_file not found, skipping" | tee -a "$LOGFILE"
      continue
    fi
  fi

  # Skip if script has already been completed
  if is_script_completed "$script"; then
    echo "Skipping $script (already completed)" | tee -a "$LOGFILE"
    continue
  fi

  # Skip NVIDIA driver installation if no GPU is present
  if [[ "$script" == *phoenix_install_nvidia_driver.sh* ]] && ! check_nvidia_gpu; then
    mark_script_completed "$script"
    continue
  fi

  echo "Starting execution of: $script" | tee -a "$LOGFILE"
  bash -c "$script" | tee -a "$LOGFILE"
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to execute $script. Exiting." | tee -a "$LOGFILE"
    exit 1
  fi
  echo "Successfully completed: $script" | tee -a "$LOGFILE"
  mark_script_completed "$script"
done

echo "[$(date)] Completed Proxmox VE setup" | tee -a "$LOGFILE"

# Clean up all automation mechanisms and state file
cleanup_automation
echo "Proxmox VE setup completed successfully. All automatic execution mechanisms have been removed to prevent future runs." | tee -a "$LOGFILE"