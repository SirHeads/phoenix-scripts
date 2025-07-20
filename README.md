# Phoenix Proxmox VE Setup Scripts

This repository contains a set of Bash scripts designed to automate the setup and configuration of a Proxmox VE server named `phoenix`. These scripts streamline tasks such as repository configuration, NVIDIA driver installation, admin user creation, ZFS pool setup, and NFS/Samba sharing. They ensure a consistent and reproducible configuration for a Proxmox VE environment.

## Introduction

The scripts in this repository automate the following tasks:
- **Repository Configuration**: Disables the Proxmox VE production and Ceph repositories, enables the no-subscription repository, installs `s-tui`, and updates the system.
- **NVIDIA Driver Installation**: Installs and verifies NVIDIA drivers for systems with NVIDIA GPUs, including blacklisting the Nouveau driver.
- **Admin User Creation**: Creates a non-root admin user with sudo and Proxmox VE admin privileges, and sets up SSH key-based authentication.
- **ZFS Pool Setup**: Configures ZFS pools (`quickOS` mirror and `fastData` single) on NVMe drives, tunes ARC cache, and uses stable `/dev/disk/by-id/` paths.
- **NFS Server Setup**: Installs and configures an NFS server with firewall rules.
- **Samba Server Setup**: Installs and configures a Samba server, user, and firewall rules.
- **ZFS Dataset and Service Setup**: Configures ZFS datasets, NFS/Samba shares, firewall rules, and Proxmox VE storage for VMs, LXC containers, and shared data.

The scripts are idempotent, meaning they can be run multiple times without causing issues, as they check for existing configurations and skip completed steps. They log all actions to `/var/log/proxmox_setup.log` for troubleshooting and auditing.

## Prerequisites

Before running the scripts, ensure the following:
- A fresh installation of Proxmox VE (based on Debian Bookworm).
- At least three NVMe drives: two 2TB drives for the `quickOS` mirrored pool and one 2TB drive for the `fastData` single pool.
- An NVIDIA GPU (for NVIDIA driver installation).
- Internet access for downloading packages.
- `wget` and `tar` installed (`apt install wget tar`).
- Root or sudo privileges to execute the scripts.

## Setup Steps

Follow these steps to download, prepare, and run the scripts:

1. **Download and Extract the Repository**:
   - Download the repository tarball to `/tmp`:
     ```bash
     wget https://github.com/SirHeads/phoenix-scripts/archive/refs/tags/v0.09.01.tar.gz -O /tmp/phoenix-scripts-0.09.01.tar.gz
     ```
   - Extract the tarball to `/tmp/phoenix-scripts-0.09.01`:
     ```bash
     tar -xzf /tmp/phoenix-scripts-0.09.01.tar.gz -C /tmp
     ```

2. **Navigate to the Scripts Directory**:
   - Change to the directory containing the scripts:
     ```bash
     cd /tmp/phoenix-scripts-0.09.01
     ```

3. **Copy Scripts to `/usr/local/bin`**:
   - Create the target directory and copy all scripts:
     ```bash
     mkdir -p /usr/local/bin
     cp /tmp/phoenix-scripts-0.09.01/common.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_proxmox_initial_config.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_install_nvidia_driver.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_create_admin_user.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_setup_nfs.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_setup_samba.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_setup_zfs_pools.sh \
        /tmp/phoenix-scripts-0.09.01/phoenix_setup_zfs_datasets.sh \
        /usr/local/bin
     ```
   - **Note**: Verify the version number (`0.09.01`) matches the extracted directory path. Adjust if necessary (e.g., `0.09.02`).

4. **Set Script Permissions**:
   - Make the scripts executable:
     ```bash
     chmod +x /usr/local/bin/*.sh
     ```

5. **Run the Scripts in Order**:
   - Execute the scripts in the following sequence to ensure proper configuration:
     ```bash
     /usr/local/bin/phoenix_proxmox_initial_config.sh
     /usr/local/bin/phoenix_install_nvidia_driver.sh
     /usr/local/bin/phoenix_create_admin_user.sh
     /usr/local/bin/phoenix_setup_nfs.sh
     /usr/local/bin/phoenix_setup_samba.sh
     /usr/local/bin/phoenix_setup_zfs_pools.sh
     /usr/local/bin/phoenix_setup_zfs_datasets.sh
     ```
   - **Optional**: Use the `--no-reboot` flag with `phoenix_proxmox_initial_config.sh`, `phoenix_install_nvidia_driver.sh`, or `phoenix_create_admin_user.sh` to skip automatic reboots (e.g., `/usr/local/bin/phoenix_proxmox_initial_config.sh --no-reboot`).

6. **Reboot the System**:
   - After running all scripts, reboot to apply changes:
     ```bash
     reboot
     ```
   - If the `--no-reboot` flag was used, reboot manually when prompted.

## Script Details

- **`common.sh`** (v1.1.1):
  - Defines shared functions used by all scripts, including logging setup, root privilege checks, command retry logic, and package installation checks.
  - Logs to `/var/log/proxmox_setup.log`.

- **`phoenix_proxmox_initial_config.sh`** (v1.1.0):
  - Configures Proxmox VE repositories (disables production and Ceph, enables no-subscription).
  - Installs `s-tui` for system monitoring.
  - Sets up logging and log rotation.
  - Updates and upgrades the system.

- **`phoenix_install_nvidia_driver.sh`** (v1.0.3):
  - Blacklists the Nouveau driver.
  - Installs Proxmox VE kernel headers, NVIDIA CUDA repository, `nvidia-driver-assistant`, `nvidia-open`, and `nvtop`.
  - Verifies driver installation with `nvidia-smi`.
  - Updates initramfs and prompts for system update and reboot.

- **`phoenix_create_admin_user.sh`** (v1.4.2):
  - Creates a non-root admin user with sudo and Proxmox VE admin privileges.
  - Supports optional SSH key-based authentication.
  - Updates the system and prompts for reboot.

- **`phoenix_setup_nfs.sh`** (v1.0.3):
  - Installs and configures an NFS server with `nfs-kernel-server` and `nfs-common`.
  - Sets up firewall rules for NFS (ports 111, 2049), SSH (port 22), and Proxmox UI (port 8006).
  - Verifies NFS services and responsiveness with a temporary export.

- **`phoenix_setup_samba.sh`** (v1.0.4):
  - Installs and configures a Samba server with `samba` and `smbclient`.
  - Prompts for Samba user credentials and configures the user.
  - Sets up firewall rules for Samba (ports 137, 138, 139, 445), SSH, and Proxmox UI.
  - Verifies Samba services and responsiveness with a temporary share.

- **`phoenix_setup_zfs_pools.sh`** (v1.0.2):
  - Configures two ZFS pools: `quickOS` (mirrored, two 2TB NVMe drives) and `fastData` (single, one 2TB NVMe drive).
  - Checks ZFS version for autotrim support, falling back to periodic `fstrim` if unsupported.
  - Wipes drives, creates pools with stable `/dev/disk/by-id/` paths, and tunes ARC cache to 24GB.
  - Verifies drive availability and pool creation.

- **`phoenix_setup_zfs_datasets.sh`** (v1.0.13):
  - Creates ZFS datasets: `quickOS/disks-vm`, `quickOS/disks-lxc`, `quickOS/shared-prod-data`, `quickOS/shared-prod-data-sync`, `fastData/shared-test-data`, `fastData/shared-test-data-sync`, `fastData/shared-backups`, `fastData/shared-iso`, `fastData/shared-bulk-data`.
  - Configures NFS and Samba shares for shared datasets.
  - Registers datasets with Proxmox VE storage for VM/LXC disks, backups, and ISOs.
  - Verifies mountpoints, NFS exports, and dataset responsiveness (local, NFS, and Samba access).

## Troubleshooting

- **Script Fails to Run**:
  - Ensure scripts are run as root (`sudo`) and are executable (`ls -l /usr/local/bin/ | grep .sh`).
  - Check `/var/log/proxmox_setup.log` for detailed error messages.

- **Download or Extraction Fails**:
  - Verify the tarball URL and ensure `wget` and `tar` are installed (`apt install wget tar`).
  - Check disk space in `/tmp` (`df -h /tmp`).

- **Copy Command Fails**:
  - Confirm the version number (`0.09.01`) matches the extracted directory (`ls /tmp/phoenix-scripts-0.09.01/`).
  - Ensure all scripts exist in the source directory.

- **Package Installation Issues**:
  - Verify internet connectivity (`ping 8.8.8.8`) and repository configurations (`cat /etc/apt/sources.list`).
  - Run `apt update` to refresh package lists.

- **ZFS Pool Creation Fails**:
  - Ensure NVMe drives are not in use (`lsblk -d | grep nvme`) and are properly connected.
  - Verify `/dev/disk/by-id/` paths (`ls -l /dev/disk/by-id/`).
  - Check for existing pools (`zpool status`) or mounts (`mount | grep nvme`).

- **NFS or Samba Access Issues**:
  - Check firewall rules (`ufw status` or `iptables -L`).
  - Verify service status (`systemctl status nfs-kernel-server smbd nmbd`).
  - Test NFS mounts (`mount -t nfs 10.0.0.13:/quickOS/shared-prod-data /mnt/test`) or Samba shares (`smbclient -L //localhost -U <username>`).

- **SSH Issues**:
  - Verify SSH configuration (`cat /etc/ssh/sshd_config`) and ensure the correct port is open.
  - Check logs in `/var/log/proxmox_setup.log` for SSH-related errors.

- **Log Rotation Issues**:
  - Ensure `logrotate` is installed (`apt install logrotate`).
  - Verify configuration syntax (`logrotate -d /etc/logrotate.d/proxmox_setup`).

## Notes

- All scripts log to `/var/log/proxmox_setup.log`. Review this file for setup details or errors.
- Log rotation is configured in `/etc/logrotate.d/proxmox_setup` to manage log file size.
- The scripts assume a default subnet of `10.0.0.0/24` and NFS server IP of `10.0.0.13`. Adjust as needed during prompts.
- The `fastData` pool uses a single 2TB NVMe drive, not 4TB as may be noted elsewhere.
- Scripts are designed for Proxmox VE on Debian Bookworm with ZFS and NVMe drives.
- For advanced customization, refer to the [Proxmox VE documentation](https://pve.proxmox.com/pve-docs/).

## Conclusion

By following these steps, you will have a fully configured Proxmox VE server with ZFS storage, NFS and Samba sharing, NVIDIA driver support, and a non-root admin user. For further assistance, consult the [Proxmox VE documentation](https://pve.proxmox.com/pve-docs/) or seek help from the community.