# Phoenix Scripts for Proxmox VE Setup

## Overview
The Phoenix Scripts project provides a robust suite of Bash scripts to automate the configuration of a Proxmox Virtual Environment (VE) server. Developed by SirHeads, these scripts streamline the setup of a virtualization platform optimized for AI, machine learning, and development workloads. The scripts handle system configuration, NVIDIA driver installation, admin user creation, ZFS storage pools, NFS, and Samba services, ensuring a secure, efficient, and production-ready server.

## Features
The Phoenix Scripts automate the following tasks on a Proxmox VE 8.x server:
- **Initial System Configuration**: Updates packages, sets timezone and NTP, configures static networking, and secures the server with UFW firewall rules.
- **NVIDIA Driver Installation**: Installs NVIDIA driver (version 575.57.08) and CUDA (version 12.9) for GPU-accelerated virtualization, with automatic GPU detection.
- **Admin User Creation**: Creates a secure admin user with sudo and Proxmox admin privileges, supporting optional SSH key setup.
- **ZFS Storage Setup**: Configures two ZFS pools (`quickOS` for mirrored NVMe drives, `fastData` for a single drive) with datasets for VMs, containers, shared data, and backups.
- **NFS Server Configuration**: Sets up an NFS server with exports for all datasets in `NFS_DATASET_LIST`, integrated with Proxmox storage.
- **Samba File Sharing**: Configures Samba shares for cross-platform access to shared datasets, secured with user authentication.
- **Orchestration**: A master script (`master_setup.sh`) ensures correct execution order, dependency checks, and state tracking for reliable setup.

## Requirements
To use the Phoenix Scripts, ensure the following:
- **Hardware**:
  - A server with Proxmox VE 8.x installed (based on Debian 12).
  - At least two NVMe drives for the `quickOS` mirrored pool and one drive for the `fastData` pool.
  - An optional NVIDIA GPU compatible with driver version 575.57.08.
  - Network connectivity with a valid subnet (e.g., `192.168.0.0/24`) and a static IP for the server.
- **Software**:
  - Proxmox VE environment with root access.
  - Internet access for downloading packages and the script tarball.
  - `wget`, `tar`, and `bash` (included by default in Proxmox VE).
- **Permissions**:
  - Root access to execute scripts.
  - Write permissions for `/usr/local/bin/` and `/var/log/`.
- **Configuration**:
  - Optionally edit `phoenix_config.sh` to customize `PROXMOX_NFS_SERVER`, `DEFAULT_SUBNET`, `QUICKOS_DRIVES`, or `FASTDATA_DRIVE`.

## Installation
Follow these steps to download, deploy, and execute the Phoenix Scripts:

1. **Download the Script Package**:
   ```bash
   wget https://github.com/SirHeads/phoenix-scripts/archive/refs/tags/v0.10.02.tar.gz -O phoenix-scripts-v0.10.02.tar.gz
   ```

2. **Extract the Scripts**:
   ```bash
   tar -xzf phoenix-scripts-v0.10.02.tar.gz
   ```

3. **Copy Scripts to `/usr/local/bin`**:
   ```bash
   sudo mkdir -p /usr/local/bin
   sudo cp phoenix-scripts-0.10.02/*.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/*.sh
   ```

4. **Configure Log Rotation**:
   Create a logrotate configuration to manage `/var/log/proxmox_setup.log`:
   ```bash
   sudo bash -c 'cat << EOF > /etc/logrotate.d/proxmox_setup
   /var/log/proxmox_setup.log {
       weekly
       rotate 4
       compress
       missingok
       notifempty
       create 664 root adm
   }
   EOF'
   ```

5. **Run the Master Setup Script**:
   Execute as root to orchestrate the setup:
   ```bash
   sudo bash /usr/local/bin/master_setup.sh
   ```

6. **Monitor Progress**:
   View real-time logs:
   ```bash
   tail -f /var/log/proxmox_setup.log
   ```

7. **Verify Setup**:
   Confirm successful configuration:
   - System updates: `apt list --upgradable`
   - NVIDIA driver: `nvidia-smi`
   - Admin user: `id $ADMIN_USERNAME` (default: `adminuser`)
   - ZFS pools: `zpool list`
   - ZFS datasets: `zfs list`
   - NFS exports: `exportfs -v`
   - Samba shares: `testparm`

## Script Details
The `master_setup.sh` script orchestrates the following scripts in order:

1. **`phoenix_proxmox_initial_setup.sh`** (v1.0.5):
   - Updates system packages, configures timezone, NTP, and static networking.
   - Sets up UFW with rules for SSH (22), Proxmox GUI (8006), NFS (2049, 111), and Samba (137, 138, 139, 445).
   - Exports `IP_ADDRESS` for NFS server configuration.

2. **`phoenix_install_nvidia_driver.sh`** (v1.0.4):
   - Installs NVIDIA driver and CUDA if an NVIDIA GPU is detected (`lspci | grep -i nvidia`).
   - Uses `--no-reboot` to avoid interrupting setup.
   - Verifies driver installation with `nvidia-smi`.

3. **`phoenix_create_admin_user.sh`** (v1.0.4):
   - Creates a user (default: `adminuser`) with sudo and Proxmox admin privileges.
   - Supports optional SSH key setup and validates password security (8+ characters, 1 special character).

4. **`phoenix_setup_zfs_pools.sh`** (v1.0.4):
   - Creates `quickOS` (mirrored pool on two NVMe drives) and `fastData` (single drive pool).
   - Validates drive availability and sets ZFS ARC limit to 30GB (requires 60GB+ RAM).
   - Prompts for drives if not set in `phoenix_config.sh`.

5. **`phoenix_setup_zfs_datasets.sh`** (v1.0.5):
   - Creates datasets on `quickOS` (`vm-disks`, `lxc-disks`, `shared-prod-data`, `shared-prod-data-sync`, `shared-backups`) and `fastData` (`shared-test-data`, `shared-iso`, `shared-bulk-data`).
   - Sets mount points to `/mnt/pve/<dataset>` and integrates with Proxmox storage (`pvesm`).

6. **`phoenix_setup_nfs.sh`** (v1.0.5):
   - Installs and configures an NFS server with exports for all datasets in `NFS_DATASET_LIST` (e.g., `quickOS/shared-prod-data`, `fastData/shared-test-data`).
   - Validates network connectivity using `check_network_connectivity` and `check_interface_in_subnet`.
   - Integrates NFS shares with Proxmox storage.

7. **`phoenix_setup_samba.sh`** (v1.0.4):
   - Configures Samba shares for `shared-prod-data`, `shared-prod-data-sync`, and `shared-backups`.
   - Uses the admin user created by `phoenix_create_admin_user.sh` for authentication.
   - Sets firewall rules for Samba ports.

8. **`phoenix_config.sh`** (v1.2.1):
   - Defines variables like `PROXMOX_NFS_SERVER`, `DEFAULT_SUBNET`, `QUICKOS_DATASET_LIST`, and `FASTDATA_DATASET_LIST`.
   - Validates IP and subnet formats for reliability.

9. **`common.sh`** (v1.2.4):
   - Provides shared functions for error handling, logging, ZFS operations, and network checks (`check_network_connectivity`, `check_internet_connectivity`, `check_interface_in_subnet`).
   - Ensures consistent behavior across all scripts.

10. **`master_setup.sh`** (v1.1.0):
    - Orchestrates script execution with state tracking (`/var/log/proxmox_setup_state`).
    - Prompts for admin credentials and ZFS drives if not predefined.
    - Ensures dependencies (e.g., `zfsutils-linux`) and handles reboots with a systemd service.

## Notes
- **Execution Order**: Scripts must run in the order defined in `master_setup.sh` to satisfy dependencies (e.g., ZFS pools before datasets, network setup before NFS).
- **Error Handling**: Scripts include retries, detailed logging to `/var/log/proxmox_setup.log`, and validation for inputs (e.g., IPs, drives, usernames).
- **Customization**: Edit `phoenix_config.sh` to adjust `PROXMOX_NFS_SERVER`, `DEFAULT_SUBNET`, or drive settings. `master_setup.sh` prompts for unset values.
- **Security**: Passwords require 8+ characters with at least one special character. UFW rules restrict access to necessary services.
- **Hardware**: Verify NVMe drive names (e.g., `nvme0n1`, `nvme1n1`, `sdb`) using `lsblk`. Ensure 60GB+ RAM for ZFS ARC settings.

## Troubleshooting
- **Log File**: Check `/var/log/proxmox_setup.log` for errors and progress.
- **Script Failures**: Verify prerequisites (e.g., internet, drive availability). Rerun `master_setup.sh` to resume from the last completed step.
- **NVIDIA Issues**: Confirm GPU detection (`lspci | grep -i nvidia`) and driver status (`nvidia-smi`).
- **ZFS Issues**: Check pool status (`zpool status`) and dataset mounts (`zfs list`). Use `--force-wipe` in `phoenix_setup_zfs_pools.sh` if drives have existing partitions.
- **NFS/Samba Issues**: Verify services (`systemctl status nfs-kernel-server smbd nmbd`) and firewall rules (`ufw status`). Test NFS exports (`exportfs -v`) and Samba shares (`smbclient -L //$PROXMOX_NFS_SERVER`).

## Contributing
Contributions are welcome! Fork the repository, make changes, and submit a pull request. Ensure compatibility with Proxmox VE 8.x and consistent logging to `/var/log/proxmox_setup.log`.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact
For questions or feedback, visit the [GitHub Issues](https://github.com/SirHeads/phoenix-scripts/issues) page.