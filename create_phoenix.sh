#!/bin/bash

# create_phoenix.sh
# Orchestrates the execution of all Proxmox VE setup scripts for the Phoenix server
# Version: 1.2.4
# Author: Heads, Grok, Devstral

# Log file and state file
LOGFILE="/var/log/proxmox_setup.log"
STATE_FILE="/var/log/proxmox_setup_state"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Ensure log file exists and is writable
touch "$LOGFILE" || { echo "Error: Cannot create log file $LOGFILE"; exit 1; }
chmod 644 "$LOGFILE"
echo "[$TIMESTAMP] Initialized logging for create_phoenix.sh" >> "$LOGFILE"

# Ensure state file exists
touch "$STATE_FILE" || { echo "Error: Cannot create state file $STATE_FILE"; exit 1; }
chmod 644 "$STATE_FILE"
echo "[$TIMESTAMP] Initialized state file: $STATE_FILE" >> "$LOGFILE"

# Source configuration
source /usr/local/bin/phoenix_config.sh || { echo "Error: Failed to source phoenix_config.sh" | tee -a "$LOGFILE"; exit 1; }
echo "[$TIMESTAMP] Configuration variables loaded" >> "$LOGFILE"

# Function to check if the script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "[$TIMESTAMP] Verified script is running as root" >> "$LOGFILE"
}

# Function to check if a script has already been completed
is_script_completed() {
    local script="$1"
    grep -Fx "$script" "$STATE_FILE" >/dev/null
}

# Function to mark a script as completed
mark_script_completed() {
    local script="$1"
    echo "$script" >> "$STATE_FILE" || { echo "Error: Failed to update $STATE_FILE" | tee -a "$LOGFILE"; exit 1; }
    echo "[$TIMESTAMP] Marked $script as completed in $STATE_FILE" >> "$LOGFILE"
}

# Function to prompt for admin credentials if not set
prompt_for_credentials() {
    if [[ -z "$ADMIN_USERNAME" ]]; then
        read -p "Enter admin username for phoenix_create_admin_user.sh [heads]: " ADMIN_USERNAME
        ADMIN_USERNAME=${ADMIN_USERNAME:-heads}
        echo "[$TIMESTAMP] Set ADMIN_USERNAME to $ADMIN_USERNAME" >> "$LOGFILE"
    fi
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        read -s -p "Enter password for admin user (min 8 chars, 1 special char) [Kick@$$2025]: " ADMIN_PASSWORD
        echo
        ADMIN_PASSWORD=${ADMIN_PASSWORD:-Kick@$$2025}
        if [[ ! "$ADMIN_PASSWORD" =~ [[:punct:]] || ${#ADMIN_PASSWORD} -lt 8 ]]; then
            echo "Error: Password must be at least 8 characters long and contain at least one special character." | tee -a "$LOGFILE"
            exit 1
        fi
        echo "[$TIMESTAMP] Set ADMIN_PASSWORD" >> "$LOGFILE"
    fi
}

# Function to get NVMe drives and their sizes
get_nvme_drives() {
    local drives=()
    local drive_info=()
    while IFS= read -r line; do
        local dev_name=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local by_id=$(ls -l /dev/disk/by-id/ | grep -E "nvme-.*${dev_name}$" | awk '{print $9}' | head -1)
        if [[ -n "$by_id" ]]; then
            drives+=("/dev/disk/by-id/$by_id")
            drive_info+=("$by_id:$size")
        fi
    done < <(lsblk -d -o NAME,SIZE,TYPE | grep nvme | awk '$3 == "disk"')
    echo "${drives[*]}|${drive_info[*]}"
}

# Function to prompt for ZFS drives
prompt_for_drives() {
    local valid=false
    local drive_array drive_info drives
    IFS='|' read -r drives drive_info <<< "$(get_nvme_drives)"
    drive_array=($drive_info)
    
    if [[ ${#drive_array[@]} -lt 3 ]]; then
        echo "Error: At least three NVMe drives are required (two for quickOS, one for fastData)." | tee -a "$LOGFILE"
        exit 1
    fi

    while [[ "$valid" == false ]]; do
        echo "Available NVMe drives:"
        local i=1
        for info in "${drive_array[@]}"; do
            local by_id=$(echo "$info" | cut -d':' -f1)
            local size=$(echo "$info" | cut -d':' -f2)
            echo "  $i. $by_id ($size)"
            ((i++))
        done

        # Prompt for quickOS drives
        if [[ -z "$QUICKOS_DRIVES" ]] || ! validate_drives_prompt_check; then
            read -p "Enter two numbers for quickOS pool drives (e.g., 1 2): " quickos_input
            if [[ ! "$quickos_input" =~ ^[0-9]+\ [0-9]+$ ]]; then
                echo "Error: Please enter two numbers separated by a space." | tee -a "$LOGFILE"
                continue
            fi
            local num1=$(echo "$quickos_input" | awk '{print $1}')
            local num2=$(echo "$quickos_input" | awk '{print $2}')
            if [[ $num1 -lt 1 || $num1 -gt ${#drive_array[@]} || $num2 -lt 1 || $num2 -gt ${#drive_array[@]} || $num1 == $num2 ]]; then
                echo "Error: Invalid or duplicate drive numbers. Choose two different numbers between 1 and ${#drive_array[@]}." | tee -a "$LOGFILE"
                continue
            fi
            QUICKOS_DRIVES="${drive_array[$((num1-1))]%%:*} ${drive_array[$((num2-1))]%%:*}"
            echo "[$TIMESTAMP] Set QUICKOS_DRIVES to $QUICKOS_DRIVES" >> "$LOGFILE"
        fi

        # Prompt for fastData drive
        if [[ -z "$FASTDATA_DRIVE" ]] || ! validate_drives_prompt_check; then
            echo "Available NVMe drives (excluding quickOS drives):"
            local quickos1=$(echo "$QUICKOS_DRIVES" | awk '{print $1}')
            local quickos2=$(echo "$QUICKOS_DRIVES" | awk '{print $2}')
            local i=1
            for info in "${drive_array[@]}"; do
                local by_id=$(echo "$info" | cut -d':' -f1)
                if [[ "$by_id" != "$quickos1" && "$by_id" != "$quickos2" ]]; then
                    local size=$(echo "$info" | cut -d':' -f2)
                    echo "  $i. $by_id ($size)"
                    ((i++))
                fi
            done
            read -p "Enter number for fastData pool drive (e.g., 3): " fastdata_input
            if [[ ! "$fastdata_input" =~ ^[0-9]+$ ]]; then
                echo "Error: Please enter a single number." | tee -a "$LOGFILE"
                continue
            fi
            if [[ $fastdata_input -lt 1 || $fastdata_input -gt ${#drive_array[@]} ]]; then
                echo "Error: Invalid drive number. Choose a number between 1 and ${#drive_array[@]}." | tee -a "$LOGFILE"
                continue
            fi
            FASTDATA_DRIVE="${drive_array[$((fastdata_input-1))]%%:*}"
            echo "[$TIMESTAMP] Set FASTDATA_DRIVE to $FASTDATA_DRIVE" >> "$LOGFILE"
        fi

        if validate_drives_prompt_check; then
            valid=true
        else
            echo "Error: Invalid drive selection. Please try again." | tee -a "$LOGFILE"
            QUICKOS_DRIVES=""
            FASTDATA_DRIVE=""
        fi
    done
}

# Function to validate drives during prompt (preliminary check)
validate_drives_prompt_check() {
    local quickos1=$(echo "$QUICKOS_DRIVES" | awk '{print $1}')
    local quickos2=$(echo "$QUICKOS_DRIVES" | awk '{print $2}')
    local drive_list=("/dev/disk/by-id/$quickos1" "/dev/disk/by-id/$quickos2" "/dev/disk/by-id/$FASTDATA_DRIVE")

    # Check if all drives exist
    for drive in "${drive_list[@]}"; do
        if [[ ! -b "$drive" ]]; then
            echo "Error: Drive $drive does not exist." | tee -a "$LOGFILE"
            return 1
        fi
    done

    # Verify quickOS drives are distinct and have the same size
    if [[ "$quickos1" == "$quickos2" ]]; then
        echo "Error: quickOS drives must be distinct, got $quickos1 twice" | tee -a "$LOGFILE"
        return 1
    fi
    local size1=$(lsblk -b -d -o SIZE "/dev/disk/by-id/$quickos1" | grep -v SIZE)
    local size2=$(lsblk -b -d -o SIZE "/dev/disk/by-id/$quickos2" | grep -v SIZE)
    if [[ "$size1" != "$size2" ]]; then
        echo "Error: quickOS drives must have the same size. $quickos1: $size1, $quickos2: $size2" | tee -a "$LOGFILE"
        return 1
    fi

    # Verify fastData drive is distinct from quickOS drives
    if [[ "$FASTDATA_DRIVE" == "$quickos1" || "$FASTDATA_DRIVE" == "$quickos2" ]]; then
        echo "Error: fastData drive must be distinct from quickOS drives." | tee -a "$LOGFILE"
        return 1
    fi

    return 0
}

# Function to validate drives for ZFS pools
validate_drives() {
    local quickos1=$(echo "$QUICKOS_DRIVES" | awk '{print $1}')
    local quickos2=$(echo "$QUICKOS_DRIVES" | awk '{print $2}')
    local drive_list=("/dev/disk/by-id/$quickos1" "/dev/disk/by-id/$quickos2" "/dev/disk/by-id/$FASTDATA_DRIVE")

    # Verify all drives exist and are not in a ZFS pool
    for drive in "${drive_list[@]}"; do
        if [[ ! -b "$drive" ]]; then
            echo "Error: Drive $drive does not exist." | tee -a "$LOGFILE"
            exit 1
        fi
        if zpool status | grep -q "$(basename "$drive")"; then
            echo "Error: Drive $drive is already in use by another ZFS pool." | tee -a "$LOGFILE"
            exit 1
        fi
    done

    # Verify quickOS drives are distinct and have the same size
    if [[ "$quickos1" == "$quickos2" ]]; then
        echo "Error: quickOS drives must be distinct, got $quickos1 twice" | tee -a "$LOGFILE"
        exit 1
    fi
    local size1=$(lsblk -b -d -o SIZE "/dev/disk/by-id/$quickos1" | grep -v SIZE)
    local size2=$(lsblk -b -d -o SIZE "/dev/disk/by-id/$quickos2" | grep -v SIZE)
    if [[ "$size1" != "$size2" ]]; then
        echo "Error: quickOS drives must have the same size. $quickos1: $size1, $quickos2: $size2" | tee -a "$LOGFILE"
        exit 1
    fi

    # Verify fastData drive is distinct from quickOS drives
    if [[ "$FASTDATA_DRIVE" == "$quickos1" || "$FASTDATA_DRIVE" == "$quickos2" ]]; then
        echo "Error: fastData drive must be distinct from quickOS drives." | tee -a "$LOGFILE"
        exit 1
    fi

    # Convert to full /dev/disk/by-id/ paths for script execution
    QUICKOS_DRIVES="/dev/disk/by-id/$quickos1 /dev/disk/by-id/$quickos2"
    FASTDATA_DRIVE="/dev/disk/by-id/$FASTDATA_DRIVE"
    export QUICKOS_DRIVES FASTDATA_DRIVE
    echo "[$TIMESTAMP] Validated drives: $QUICKOS_DRIVES $FASTDATA_DRIVE" >> "$LOGFILE"
}

# Function to check for NVIDIA GPU presence
check_nvidia_gpu() {
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        echo "[$TIMESTAMP] NVIDIA GPU detected" >> "$LOGFILE"
        return 0
    else
        echo "[$TIMESTAMP] No NVIDIA GPU detected, skipping phoenix_install_nvidia_driver.sh" | tee -a "$LOGFILE"
        return 1
    fi
}

# Function to clean up state file
cleanup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        echo "[$TIMESTAMP] Removed state file: $STATE_FILE" >> "$LOGFILE"
    fi
}

# Configuration variables (defaults)
ADMIN_USERNAME=${ADMIN_USERNAME:-heads}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Kick@$$2025}
QUICKOS_DRIVES=${QUICKOS_DRIVES:-""}
FASTDATA_DRIVE=${FASTDATA_DRIVE:-""}
SMB_USER=${SMB_USER:-$ADMIN_USERNAME}
SMB_PASSWORD=${SMB_PASSWORD:-$ADMIN_PASSWORD}
export ADMIN_USERNAME ADMIN_PASSWORD QUICKOS_DRIVES FASTDATA_DRIVE SMB_USER SMB_PASSWORD

# List of setup scripts to execute
scripts=(
    "/usr/local/bin/phoenix_proxmox_initial_setup.sh"
    "/usr/local/bin/phoenix_install_nvidia_driver.sh"
    "/usr/local/bin/phoenix_create_admin_user.sh -u \"$ADMIN_USERNAME\" -p \"$ADMIN_PASSWORD\""
    "if ! dpkg-query -W zfsutils-linux > /dev/null; then apt-get update && apt-get install -y zfsutils-linux; fi"
    "/usr/local/bin/phoenix_setup_zfs_pools.sh -q \"$QUICKOS_DRIVES\" -f \"$FASTDATA_DRIVE\""
    "/usr/local/bin/phoenix_setup_zfs_datasets.sh -q \"vm-disks lxc-disks shared-prod-data shared-prod-data-sync\" -f \"shared-test-data shared-backups shared-iso shared-bulk-data shared-test-data-sync\""
    "/usr/local/bin/phoenix_setup_nfs.sh --no-reboot"
    "/usr/local/bin/phoenix_setup_samba.sh -p \"$SMB_PASSWORD\""
)

# Main execution
check_root
prompt_for_credentials
prompt_for_drives
validate_drives

for script in "${scripts[@]}"; do
    # Check if the script file exists (skip for inline commands like zfsutils-linux check)
    if [[ "$script" != *"dpkg-query"* ]]; then
        script_file=$(echo "$script" | awk '{print $1}')
        if [[ ! -f "$script_file" ]]; then
            echo "Error: Script $script_file not found" | tee -a "$LOGFILE"
            exit 1
        fi
    fi

    # Skip if script has already been completed
    if is_script_completed "$script"; then
        echo "[$TIMESTAMP] Skipping $script (already completed)" >> "$LOGFILE"
        continue
    fi

    # Skip NVIDIA driver installation if no GPU is present
    if [[ "$script" == *phoenix_install_nvidia_driver.sh* ]] && ! check_nvidia_gpu; then
        mark_script_completed "$script"
        continue
    fi

    echo "[$TIMESTAMP] Starting execution of: $script" >> "$LOGFILE"
    bash -c "$script" | tee -a "$LOGFILE"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "[$TIMESTAMP] Error: Failed to execute $script. Exiting." | tee -a "$LOGFILE"
        exit 1
    fi
    mark_script_completed "$script"
    echo "[$TIMESTAMP] Successfully completed: $script" >> "$LOGFILE"
done

echo "[$TIMESTAMP] Completed Phoenix Proxmox VE setup" >> "$LOGFILE"
cleanup_state
echo "Phoenix Proxmox VE setup completed successfully. State file removed for clean manual rerun." | tee -a "$LOGFILE"
exit 0