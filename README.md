# Proxmox VE Setup Scripts

## Overview
This repository contains a set of bash scripts to automate the initial setup of Proxmox Virtual Environment (Proxmox VE). The master script orchestrates the entire process, ensuring that each step is executed in sequence.

## Requirements
- Root access on Proxmox VE node.
- Active internet connection for package downloads.
- Properly configured DNS and NTP services.

## Scripts Overview

### 1. `phoenix_config.sh`
Central configuration file containing common variables and settings used across all scripts:
- Logging paths
- Networking configurations (NFS server IP, subnet)
- Samba user details
- ZFS pool and dataset names

### 2. `common.sh`
Contains reusable functions shared across setup scripts:
- Root check (`check_root`)
- Package management (`check_package`, `retry_command`)
- Network connectivity checks
- Logging setup
- Common system administration tasks

### 3. `master_setup.sh`
The master orchestration script that runs all the individual configuration scripts in sequence.
- Sources common functions and configurations.
- Executes each script while handling errors and logging progress.

### Individual Configuration Scripts
Each of these scripts is designed to configure a specific aspect of Proxmox VE:

1. **Initial System Setup**
   - `phoenix_proxmox_initial_setup.sh`
     - Updates the system, configures NTP, sets up networking, and performs initial security hardening.

2. **NVIDIA Driver Installation**
   - `phoenix_install_nvidia_driver.sh`
     - Installs NVIDIA drivers on Proxmox VE to enable GPU passthrough for virtual machines.

3. **Admin User Creation**
   - `phoenix_create_admin_user.sh`
     - Creates a new administrative user with sudo privileges and sets up SSH key authentication (optional).

4. **NFS Server Setup**
   - `phoenix_setup_nfs.sh`
     - Installs and configures an NFS server to provide shared storage for virtual machines.

5. **Samba Configuration**
   - `phoenix_setup_samba.sh`
     - Sets up a Samba file server to share data across the network with Windows clients.

6. **ZFS Pool Setup**
   - `phoenix_setup_zfs_pools.sh`
     - Creates ZFS storage pools for efficient and redundant data storage.

7. **ZFS Dataset Creation**
   - `phoenix_setup_zfs_datasets.sh`
     - Configures ZFS datasets within existing ZFS pools to organize data.

## Usage Instructions

### Preparation
1. Clone the repository:
   ```bash
   git clone https://github.com/your-repo/proxmox-ve-setup.git
   cd proxmox-ve-setup



### ZFS Pool Setup (Continued)
`phoenix_setup_zfs_pools.sh`
- **Purpose**: Create ZFS storage pools.
- **Key Actions**:
  - Installs ZFS utilities.
  - Prompts for data and log drives, or uses provided command-line arguments.
  - Creates ZFS pool with specified disks.
  - Adds log device if available.

### 7. ZFS Dataset Creation
`phoenix_setup_zfs_datasets.sh`
- **Purpose**: Configure datasets within existing ZFS pools to organize data.
- **Key Actions**:
  - Verifies the existence of the specified ZFS pool.
  - Creates datasets with appropriate mount points based on provided list.
  - Ensures each dataset is correctly configured and mounted.

## Common Functions

### Logging
- All scripts use centralized logging via `$LOGFILE` (defined in `phoenix_config.sh`).

### Error Handling
- Each script checks if it successfully sources necessary files (`common.sh`, `phoenix_config.sh`). If not, it exits with an error message.
- The master setup script logs errors and exits if any individual script fails.

### Network Checks
- Several scripts include network connectivity checks to ensure proper configuration (e.g., NFS server setup).

## Version History
- **v0.10.01**: Initial release of the orchestrated setup process with detailed documentation.