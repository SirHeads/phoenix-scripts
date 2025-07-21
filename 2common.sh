#!/bin/bash

# common.sh
# Shared functions for Proxmox VE setup scripts
# Version: 1.1.1
# Author: Heads, Grok, Devstral
# Usage: Source this script in other setup scripts to use common functions
# Note: Configure log rotation for $LOGFILE using /etc/logrotate.d/proxmox_setup

# Constants
LOGFILE="/var/log/proxmox_setup.log"
readonly LOGFILE
LOGDIR=$(dirname "$LOGFILE")

# Ensure log directory exists and is writable
setup_logging() {
  mkdir -p "$LOGDIR" || { echo "Error: Failed to create log directory $LOGDIR"; exit 1; }
  touch "$LOGFILE" || { echo "Error: Failed to create log file $LOGFILE"; exit 1; }
  chmod 664 "$LOGFILE" || { echo "Error: Failed to set permissions on $LOGFILE"; exit 1; }
  echo "[$(date)] Initialized logging for $(basename "$0")" >> "$LOGFILE"
}

# Check if script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo" | tee -a "$LOGFILE"
    exit 1
  fi
}

# Retry a command up to 3 times with delay, capturing error output
retry_command() {
  local cmd="$1"
  local retries=3
  local delay=5
  local count=0
  local error_output

  until error_output=$(eval "$cmd" 2>&1 >> "$LOGFILE"); do
    count=$((count + 1))
    if [[ $count -ge $retries ]]; then
      echo "Error: Command failed after $retries attempts: $cmd" | tee -a "$LOGFILE"
      echo "Error output: $error_output" | tee -a "$LOGFILE"
      exit 1
    fi
    echo "Warning: Command failed, retrying ($count/$retries)... Error: $error_output" | tee -a "$LOGFILE"
    sleep "$delay"
  done
  echo "[$(date)] Successfully executed: $cmd" >> "$LOGFILE"
}

# Check if a package is installed
check_package() {
  local package="$1"
  if dpkg -l | grep -q "$package"; then
    echo "Package $package already installed, skipping" | tee -a "$LOGFILE"
    return 0
  fi
  return 1
}

# Initialize logging
setup_logging