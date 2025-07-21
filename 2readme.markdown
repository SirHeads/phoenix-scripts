# Proxmox VE Setup Scripts

This repository contains a set of bash scripts designed to automate the setup and configuration of a Proxmox VE server named phoenix. The scripts handle tasks such as configuring repositories, installing the NVIDIA driver, creating an admin user, and setting up ZFS pools with NFS and Samba sharing. These scripts streamline the initial setup process and ensure a consistent configuration.

## Introduction

The scripts in this repository automate the following tasks:
- **Repository Configuration**: Disables the production and Ceph repositories, enables the no-subscription repository, and updates the system.
- **NVIDIA Driver Installation**: Installs and verifies the NVIDIA driver for systems with NVIDIA GPUs.
- **Admin User Creation**: Creates a non-root admin user with sudo and Proxmox admin privileges, sets up SSH key-based authentication, and configures the SSH port.
- **ZFS Pool Setup**: Configures ZFS pools (`quickOS` mirror and `fastData` single) for NVMe drives, using stable `/dev/disk/by-id/` paths.
- **ZFS Dataset and Service Setup**: Configures ZFS datasets, snapshots, NFS/Samba shares, firewall rules, and Proxmox storage for VMs, LXC, and shared data.

These scripts are designed to be run in a specific order and are idempotent, meaning they can be run multiple times without causing issues, as they check for existing configurations and skip steps that have already been completed.

## Prerequisites

Before running the scripts, ensure that you have the following:
- A fresh installation of Proxmox VE.
- At least three NVMe drives for ZFS pools: two 2TB drives for `quickOS` (mirrored) and one 2TB drive for `fastData` (single).
- An NVIDIA GPU (for driver installation).
- Internet access for downloading packages.
- `wget` and `tar` installed (`apt install wget tar`).

## Setup Steps

1. **Download and Extract the Repository**:
   - Download the repository tarball to `/tmp`:
     ```bash
     wget https://github.com/SirHeads/thinkheads-ai-ragdocs-IT/archive/refs/tags/v0.2.01.tar.gz -O /tmp/thinkheads-ai-ragdocs-IT-0.2.01.tar.gz
     ```
   - Confirm `https://github.com/your-repo/proxmox-setup-scripts/archive/refs/tags/v0.2.01.tar.gz` with the actual URL of desired repository tarball.
   - Extract the tarball to `/tmp/thinkheads-ai-ragdocs-IT-0.2.01`:
     ```bash
     tar -xzf /tmp/thinkheads-ai-ragdocs-IT-0.2.01.tar.gz -C /tmp
     mv /tmp/proxmox-setup-scripts-0.2.01 /tmp/thinkheads-ai-ragdocs-IT-0.2.01
     ```

2. **Navigate to the Scripts Directory**:
   - Change to the directory containing the scripts:
     ```bash
     cd /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts
     ```

3. **Copy Scripts to `/usr/local/bin`**:
   - Create the target directory and copy the scripts. Check version number in file path (0.2.01):
     ```bash
     mkdir -p /usr/local/bin
     cp /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/common.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_proxmox_initial_config.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_install_nvidia_driver.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_create_admin_user.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_setup_nfs.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_setup_samba.sh \  
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_setup_zfs_pools.sh \
        /tmp/thinkheads-ai-ragdocs-IT-0.2.01/shared/scripts/phoenix_setup_zfs_datasets.sh \
        /usr/local/bin
     ```
   - **Note**: Verify the version number (`0.2.01`) matches your extracted directory path. Adjust if necessary (e.g., `0.2.02`).

4. **Set Script Permissions**:
   - Make the scripts executable:
     ```bash
     chmod +x /usr/local/bin/*.sh
     ```

7. **Run the Scripts in Order**:
   - Configure repositories:
     ```bash
     /usr/local/bin/phoenix_proxmox_initial_config.sh
     ```
   - Install NVIDIA driver:
     ```bash
     /usr/local/bin/phoenix_install_nvidia_driver.sh
     ```
   - Create admin user:
     ```bash
     /usr/local/bin/phoenix_create_admin_user.sh
     ```
   - Setup NFS:
     ```bash
     /usr/local/bin/phoenix_setup_nfs.sh
     ```
   - Setup Samba:
     ```bash
     /usr/local/bin/phoenix_setup_samba.sh
     ```
   - Setup ZFS pools:
     ```bash
     /usr/local/bin/phoenix_setup_zfs_pools.sh
     ```
   - Setup ZFS datasets and services:
     ```bash
     /usr/local/bin/phoenix_setup_zfs_datasets.sh
     ```

8. **Reboot the System**:
   - After running all scripts, reboot the system to apply changes:
     ```bash
     reboot
     ```
   - If you used the `--no-reboot` flag, reboot manually.

## Script Details

## Troubleshooting

- **Script Fails to Run**: Ensure you are running the scripts as root (`sudo`) and that they are executable (`ls -l /usr/local/bin/ | grep .sh`).
- **Download or Extraction Fails**: Verify the tarball URL and ensure `wget` and `tar` are installed (`apt install wget tar`). Check available disk space in `/tmp` (`df -h /tmp`).
- **Copy Command Fails**: Verify the version number (0.1.10) in the source path matches your extracted directory. Check that all listed scripts exist (`ls /tmp/thinkheads-ai-ragdocs-IT-0.1.10/shared/scripts/`).
- **Package Installation Issues**: Confirm internet connectivity and repository configurations (`cat /etc/apt/sources.list`).
- **ZFS Pool Creation Fails**: Ensure NVMe drives are not in use and are properly connected (`lsblk -d | grep nvme`). Check `/dev/disk/by-id/` paths (`ls -l /dev/disk/by-id/`).
- **NFS or Samba Access Issues**: Check firewall rules (`iptables -L` or `firewall-cmd --list-all`) and service status (`systemctl status nfs-kernel-server smbd`).
- **SSH Issues**: Verify the SSH port and key configuration (`cat /etc/ssh/sshd_config`); check logs in `/var/log/proxmox_setup.log`.
- **Log Rotation Issues**: Ensure `logrotate` is installed (`apt install logrotate`) and check syntax (`logrotate -d /etc/logrotate.d/proxmox_setup`).

## Notes

- All scripts log actions to `/var/log/proxmox_setup.log`. Check this file for detailed setup information.
- The scripts are idempotent and can be run multiple times safely.
- Ensure the version number in the script paths (0.1.10) matches your setup to avoid errors.
- The `fastData` pool uses a 2TB NVMe drive, not 4TB as previously noted.

## Conclusion

By following these steps, you should have a fully configured Proxmox VE server with ZFS storage, NFS and Samba sharing, and an admin user set up. For further customization or issues, refer to the [Proxmox VE documentation](https://pve.proxmox.com/pve-docs/) or seek help from the community.