#!/bin/bash
# phoenix_create_storage.sh
#
# Creates Proxmox VE storage definitions for the configured ZFS datasets and directories.
# This script should be run after ZFS datasets are created but before NFS/Samba exports
# are configured by the orchestrator.
#
# Version: 1.0.2 (Fixed incorrect -shared flag for ZFS storage, aligned with config changes)
# Author: Assistant, based on Heads, Grok, Devstral's work

# --- Source common functions and configuration ---
# Assumes LOGFILE is set by the orchestrator (create_phoenix.sh)
# shellcheck source=/dev/null
if [[ -f /usr/local/bin/common.sh ]]; then
    source /usr/local/bin/common.sh || { echo "[$(date)] Error: Failed to source common.sh" | tee -a /dev/stderr; exit 1; }
else
    echo "[$(date)] Error: common.sh not found at /usr/local/bin/common.sh" | tee -a /dev/stderr
    exit 1
fi

# shellcheck source=/dev/null
if [[ -f /usr/local/bin/phoenix_config.sh ]]; then
    source /usr/local/bin/phoenix_config.sh || { echo "[$(date)] Error: Failed to source phoenix_config.sh" | tee -a /dev/stderr; exit 1; }
else
    echo "[$(date)] Error: phoenix_config.sh not found at /usr/local/bin/phoenix_config.sh" | tee -a /dev/stderr
    exit 1
fi

# Ensure the script is run as root
check_root

# Setup logging - Use LOGFILE from environment (set by orchestrator) or default
LOGFILE="${LOGFILE:-/var/log/proxmox_setup.log}"
echo "[$(date)] Starting phoenix_create_storage.sh" >> "$LOGFILE"

# --- Function to create a ZFS storage ---
# Arguments:
# $1: Storage ID (unique name for Proxmox)
# $2: ZFS Pool/Dataset (e.g., quickOS/vm-disks)
# $3: Content types (comma-separated, e.g., "images,rootdir")
# $4: Optional: Disable (0 or 1, default 0)
create_zfs_storage() {
    local storage_id="$1"
    local zfs_pool="$2"
    local content="$3"
    local disable="${4:-0}" # Default to enabled
    # local shared="${5:-0}"  # Default to not shared - IGNORED for zfspool type

    if [[ -z "$storage_id" || -z "$zfs_pool" || -z "$content" ]]; then
        echo "[$(date)] Error: create_zfs_storage requires storage_id, zfs_pool, and content." | tee -a "$LOGFILE"
        return 1
    fi

    # Check if storage already exists
    if pvesm status | grep -q "^$storage_id:"; then
        echo "[$(date)] Info: Proxmox storage '$storage_id' already exists, skipping creation." >> "$LOGFILE"
        return 0
    fi

    echo "[$(date)] Creating ZFS storage: ID=$storage_id, Pool/Dataset=$zfs_pool, Content=$content" >> "$LOGFILE"
    # Use pvesm add zfspool - REMOVED -shared flag
    if pvesm add zfspool "$storage_id" -pool "$zfs_pool" -content "$content" -disable "$disable"; then
        echo "[$(date)] Successfully created ZFS storage '$storage_id'." >> "$LOGFILE"
    else
        echo "[$(date)] Error: Failed to create ZFS storage '$storage_id'." | tee -a "$LOGFILE"
        return 1
    fi
}

# --- Function to create a Directory storage ---
# Arguments:
# $1: Storage ID (unique name for Proxmox)
# $2: Path on the filesystem (e.g., /fastData/shared-backups)
# $3: Content types (comma-separated, e.g., "backup,iso")
# $4: Optional: Disable (0 or 1, default 0)
# $5: Optional: Shared (0 or 1, default 1 for directories)
# $6: Optional: NFS Server (if path is on an NFS mount)
# $7: Optional: NFS Export (if path is on an NFS mount)
create_directory_storage() {
    local storage_id="$1"
    local path="$2"
    local content="$3"
    local disable="${4:-0}" # Default to enabled
    local shared="${5:-1}"  # Default to shared for directories
    local server="${6:-}"   # NFS Server (optional)
    local export_path="${7:-}" # NFS Export Path (optional)

    if [[ -z "$storage_id" || -z "$path" || -z "$content" ]]; then
        echo "[$(date)] Error: create_directory_storage requires storage_id, path, and content." | tee -a "$LOGFILE"
        return 1
    fi

    # Check if storage already exists
    if pvesm status | grep -q "^$storage_id:"; then
        echo "[$(date)] Info: Proxmox storage '$storage_id' already exists, skipping creation." >> "$LOGFILE"
        return 0
    fi

    local cmd="pvesm add dir $storage_id -path $path -content $content -disable $disable -shared $shared"
    # Append NFS options if provided
    if [[ -n "$server" ]]; then
        cmd="$cmd -server $server"
    fi
    if [[ -n "$export_path" ]]; then
        cmd="$cmd -export $export_path"
    fi

    echo "[$(date)] Creating Directory storage: ID=$storage_id, Path=$path, Content=$content" >> "$LOGFILE"
    # Use pvesm add dir
    if eval "$cmd"; then
        echo "[$(date)] Successfully created Directory storage '$storage_id'." >> "$LOGFILE"
    else
        echo "[$(date)] Error: Failed to create Directory storage '$storage_id'." | tee -a "$LOGFILE"
        return 1
    fi
}

# --- Function to determine content type for a dataset ---
# This parses the DATASET_STORAGE_TYPES associative array from phoenix_config.sh
# Arguments:
# $1: Full dataset path (e.g., quickOS/vm-disks, fastData/shared-backups)
# Output: Content type string for pvesm (e.g., "images", "backup", "iso")
get_content_type_for_dataset() {
    local full_dataset_path="$1"
    local storage_type_content=""

    # Check if the entry exists in the associative array
    if [[ -n "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
        # Extract content type part after the colon (e.g., from "dir:images" get "images")
        storage_type_content="${DATASET_STORAGE_TYPES[$full_dataset_path]#*:}"
        # If no colon was found, default to the whole string (fallback)
        if [[ "$storage_type_content" == "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
             storage_type_content="images" # Default fallback
        fi
    else
        # Default or error handling
        echo "[$(date)] Warning: Unknown storage type/content for dataset '$full_dataset_path'. Using 'images'." >> "$LOGFILE"
        storage_type_content="images"
    fi
    echo "$storage_type_content"
}

# --- Function to determine storage type for a dataset ---
# This parses the DATASET_STORAGE_TYPES associative array from phoenix_config.sh
# Arguments:
# $1: Full dataset path (e.g., quickOS/vm-disks, fastData/shared-backups)
# Output: Storage type string for logic (e.g., "zfspool", "dir")
get_storage_type_for_dataset() {
    local full_dataset_path="$1"
    local storage_type=""

    # Check if the entry exists in the associative array
    if [[ -n "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
        # Extract storage type part before the colon (e.g., from "dir:images" get "dir")
        storage_type="${DATASET_STORAGE_TYPES[$full_dataset_path]%:*}"
        # If no colon was found, default to "dir" (fallback assumption)
        if [[ "$storage_type" == "${DATASET_STORAGE_TYPES[$full_dataset_path]}" ]]; then
             storage_type="dir"
        fi
    else
        # Default or error handling
        echo "[$(date)] Warning: Unknown storage type for dataset '$full_dataset_path'. Using 'dir'." >> "$LOGFILE"
        storage_type="dir"
    fi
    echo "$storage_type"
}


# --- Main Execution ---
# Load configuration variables (this will validate and set defaults)
# Although sourced, explicitly calling load_config ensures variables are populated
# if this script is run standalone for testing.
load_config
echo "[$(date)] Configuration variables loaded for storage creation." >> "$LOGFILE"

# --- Create Storage Definitions based on phoenix_config.sh and storage_requirements.txt ---
# Iterate through the DATASET_STORAGE_TYPES associative array to create storages
# This makes it more dynamic and less prone to missing entries if the config changes.
echo "[$(date)] Starting to iterate through configured datasets for storage creation." >> "$LOGFILE"

for full_dataset_path in "${!DATASET_STORAGE_TYPES[@]}"; do
    echo "[$(date)] Processing dataset: $full_dataset_path" >> "$LOGFILE"

    # Determine storage and content types
    STORAGE_TYPE=$(get_storage_type_for_dataset "$full_dataset_path")
    CONTENT_TYPE=$(get_content_type_for_dataset "$full_dataset_path")

    # Derive a default storage ID (you might want a more robust mapping in config)
    # This simple approach replaces '/' with '-' and removes pool name prefix if present
    DEFAULT_STORAGE_ID="${full_dataset_path//\//-}"
    # Remove pool name prefix if it exists (e.g., quickOS-vm-disks)
    if [[ "$DEFAULT_STORAGE_ID" == "${QUICKOS_POOL}-"* ]]; then
        STORAGE_ID="${DEFAULT_STORAGE_ID/${QUICKOS_POOL}-}"
    elif [[ "$DEFAULT_STORAGE_ID" == "${FASTDATA_POOL}-"* ]]; then
        STORAGE_ID="${DEFAULT_STORAGE_ID/${FASTDATA_POOL}-}"
    else
        STORAGE_ID="$DEFAULT_STORAGE_ID"
    fi
    # Capitalize first letter of pool part for better ID (optional)
    # STORAGE_ID="$(tr '[:lower:]' '[:upper:]' <<< ${STORAGE_ID:0:1})${STORAGE_ID:1}"

    echo "[$(date)] Derived Storage ID: $STORAGE_ID, Type: $STORAGE_TYPE, Content: $CONTENT_TYPE" >> "$LOGFILE"

    case "$STORAGE_TYPE" in
        "zfspool")
            create_zfs_storage "$STORAGE_ID" "$full_dataset_path" "$CONTENT_TYPE"
            ;;
        "dir")
            # Construct mountpoint path: /$pool_name/$dataset_name
            # Assumes dataset name format is pool_name/dataset_name
            POOL_NAME="${full_dataset_path%%/*}"
            DATASET_NAME="${full_dataset_path#*/}"
            MOUNTPOINT="/$POOL_NAME/$DATASET_NAME"
            create_directory_storage "$STORAGE_ID" "$MOUNTPOINT" "$CONTENT_TYPE"
            ;;
        *)
            echo "[$(date)] Warning: Unsupported storage type '$STORAGE_TYPE' for dataset '$full_dataset_path'. Skipping." >> "$LOGFILE"
            ;;
    esac
done

# --- 9. Placeholder for storageNFS (DISABLED) ---
# As per your request and config changes, this remains disabled/commented out.
# If re-enabled, logic would need to determine if it's NFS or Directory storage
# based on config and potentially involve mounting the NFS share first.

echo "[$(date)] Completed phoenix_create_storage.sh" >> "$LOGFILE"
exit 0