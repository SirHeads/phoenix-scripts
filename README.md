# Phoenix Scripts for Proxmox VE Setup

## Overview
The Phoenix Scripts project provides a comprehensive suite of Bash scripts to automate the configuration of a Proxmox Virtual Environment (VE) server. This repository, developed by SirHeads, streamlines the setup of a robust virtualization platform for hosting AI, machine learning, and development environments. The scripts configure essential system settings, NVIDIA drivers, admin users, ZFS storage pools, NFS, and Samba services, ensuring a secure and efficient server ready for production, testing, and development workloads.

## What is Accomplished
This script package automates the following tasks on a Proxmox VE server:
- **Initial System Configuration**: Updates the system, sets timezone and NTP, configures networking, and secures the firewall with UFW.
- **NVIDIA Driver Installation**: Installs NVIDIA driver (version 575.57.08) and CUDA (version 12.9) for GPU-accelerated virtualization.
- **Admin User Creation**: Creates a secure admin user with sudo and Proxmox admin privileges, optionally setting up SSH access.
- **ZFS Storage Setup**: Configures a ZFS pool (`rpool`) with datasets for shared data, backups, and ISOs, optimized for performance.
- **NFS Server Configuration**: Sets up an NFS server with exports for shared datasets, integrated with Proxmox storage.
- **Samba File Sharing**: Configures Samba shares for cross-platform file access, secured with user authentication.
- **Orchestration**: A master script ensures all setup tasks run in the correct order with robust error handling.

## Requirements
To use the Phoenix Scripts, ensure the following:
- **Hardware**:
  - A server with Proxmox VE 8.x installed.
  - At least two NVMe drives (one for data, one for ZFS log) for ZFS pool creation.
  - An NVIDIA GPU compatible with driver version 575.57.08 for GPU virtualization.
  - Network connectivity with a valid subnet (e.g., `10.0.0.0/24`) and an NFS server IP (e.g., `192.168.0.2`).
- **Software**:
  - Ubuntu-based Proxmox VE environment with root access.
  - Internet access for downloading packages and the script tarball.
  - `wget`, `tar`, and `bash` installed (typically included in Proxmox VE).
- **Permissions**:
  - Root access to execute the scripts.
  - Write permissions for `/usr/local/bin/` and `/var/log/`.
- **Configuration**:
  - Modify `phoenix_config.sh` to set your NFS server IP, subnet, and drive paths if different from defaults.

## How to Accomplish
Follow these steps to download, deploy, and execute the Phoenix Scripts:
1. **Download the Script Package**:
   - Use `wget` to download the tarball for version `v0.10.01`:
     ```bash
     wget https://github.com/SirHeads/phoenix-scripts/archive/refs/tags/v0.10.01.tar.gz -O phoenix-scripts-v0.10.01.tar.gz
     ```
2. **Extract the Scripts**:
   - Extract the tarball to a temporary directory:
     ```bash
     tar -xzf phoenix-scripts-v0.10.01.tar.gz
     ```
3. **Copy Scripts to `/usr/local/bin`**:
   - Move the scripts to `/usr/local/bin/` and set executable permissions:
     ```bash
     sudo mkdir -p /usr/local/bin
     sudo cp phoenix-scripts-0.10.01/*.sh /usr/local/bin/
     sudo chmod +x /usr/local/bin/*.sh
     ```
4. **Configure Log Rotation**:
   - Ensure the log file `/var/log/proxmox_setup.log` is rotated to manage disk space:
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
   - Execute the `master_setup.sh` script as root to orchestrate the setup:
     ```bash
     sudo bash /usr/local/bin/master_setup.sh
     ```
6. **Monitor Progress**:
   - Check the log file for detailed output:
     ```bash
     tail -f /var/log/proxmox_setup.log
     ```
7. **Verify Setup**:
   - Confirm system updates (`apt list --upgradable`), NVIDIA driver (`nvidia-smi`), admin user (`id adminuser`), ZFS pools (`zpool list`), datasets (`zfs list`), NFS exports (`exportfs -v`), and Samba shares (`testparm`).

## Details of the Process
The `master_setup.sh` script orchestrates the following scripts in sequence, each performing specific tasks:

1. **phoenix_proxmox_initial_setup.sh**:
   - Updates the system, configures timezone, NTP, and networking.
   - Sets up UFW with rules for SSH, Proxmox GUI, NFS, and Samba.
   - Logs actions to `/var/log/proxmox_setup.log`.

2. **phoenix_install_nvidia_driver.sh**:
   - Installs NVIDIA driver (575.57.08) and CUDA (12.9) without rebooting (via `--no-reboot`).
   - Verifies driver installation and module loading.
   - Skips installation if no NVIDIA GPU is detected.

3. **phoenix_create_admin_user.sh**:
   - Creates an admin user (`adminuser`) with a secure password and sudo privileges.
   - Configures optional SSH key access and adds the user to the Proxmox admin role.
   - Validates username and password formats.

4. **phoenix_setup_nfs.sh**:
   - Installs and configures an NFS server with exports for `shared-prod-data` and `shared-prod-data-sync`.
   - Integrates NFS storage with Proxmox VE (`/etc/pve/storage.cfg`).
   - Validates network connectivity and export configurations.

5. **phoenix_setup_samba.sh**:
   - Installs Samba and configures shares for `shared-prod-data`, `shared-prod-data-sync`, and `shared-backups`.
   - Sets up a Samba user (`admin`) with a secure password.
   - Configures firewall rules for Samba ports (137/udp, 138/udp, 139/tcp, 445/tcp).

6. **phoenix_setup_zfs_pools.sh**:
   - Creates a ZFS pool (`rpool`) on a user-specified data drive with an optional log drive.
   - Validates drive availability and ensures no existing partitions are used without confirmation.

7. **phoenix_setup_zfs_datasets.sh**:
   - Creates ZFS datasets (`shared-prod-data`, `shared-prod-data-sync`, `shared-test-data`, `shared-test-data-sync`, `backups`, `iso`, `bulk-data`) on `rpool`.
   - Sets mount points to `/mnt/pve/<dataset>` for consistency with NFS and Samba.

8. **phoenix_config.sh**:
   - Defines configuration variables (e.g., `PROXMOX_NFS_SERVER`, `DEFAULT_SUBNET`, `ZFS_DATASET_LIST`) used across all scripts.
   - Validates IP and subnet formats for reliability.

9. **common.sh**:
   - Provides shared functions like `check_root`, `retry_command`, `zfs_pool_exists`, and `zfs_dataset_exists` for consistent error handling and logging.

10. **master_setup.sh**:
    - Orchestrates all scripts, ensuring they run in the correct order.
    - Includes dependency checks (e.g., `zfsutils-linux`) and detailed error logging.

## Notes
- **Execution Order**: The scripts must run in the order defined in `master_setup.sh` to ensure dependencies (e.g., ZFS pools before datasets) are met.
- **Error Handling**: Each script includes robust error checking, retries, and logging to `/var/log/proxmox_setup.log` for troubleshooting.
- **Customization**: Edit `phoenix_config.sh` to adjust variables like `PROXMOX_NFS_SERVER` or `ZFS_DATASET_LIST` to match your environment.
- **Hardware-Specific**: Ensure your server has compatible NVMe drives and an NVIDIA GPU. Modify drive paths in `phoenix_setup_zfs_pools.sh` if needed.
- **Security**: The admin user password and Samba password require at least 8 characters with one special character for security.

## Troubleshooting
- **Log File**: Check `/var/log/proxmox_setup.log` for detailed error messages.
- **Script Failures**: If a script fails, review the log, verify prerequisites (e.g., internet, drive availability), and rerun `master_setup.sh`.
- **NVIDIA Issues**: Run `nvidia-smi` to verify driver installation. Ensure the GPU is recognized (`lspci | grep -i nvidia`).
- **ZFS Issues**: Check pool status (`zpool status`) and dataset mounts (`zfs list`). Ensure drives are unpartitioned or use `--force-wipe`.
- **NFS/Samba Issues**: Verify service status (`systemctl status nfs-kernel-server smbd nmbd`) and firewall rules (`ufw status`).

## Contributing
Contributions are welcome! Please fork the repository, make changes, and submit a pull request. Ensure scripts maintain compatibility with Proxmox VE 8.x and include logging to `/var/log/proxmox_setup.log`.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact
For questions or feedback, reach out via the [GitHub Issues](https://github.com/SirHeads/phoenix-scripts/issues) page.