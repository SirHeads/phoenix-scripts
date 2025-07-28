# Phoenix Proxmox VE Server Setup Scripts

Automate the configuration and provisioning of a Proxmox Virtual Environment (VE) server named "Phoenix". This collection of Bash scripts streamlines the setup process for a specific hardware and use-case scenario, focusing on ZFS storage, NVIDIA GPU support, and shared data access via Samba. (NFS setup is included but storage pools/datasets for it are disabled in the current 3-drive configuration).

## Overview

The "Phoenix" setup aims to transform a fresh Proxmox VE installation into a ready-to-use server with a predefined storage layout, user accounts, network configuration, and essential services. The core storage utilizes ZFS for data integrity and performance, organized into distinct pools for operating system/data and bulk storage. The scripts handle initial OS configuration, ZFS pool and dataset creation, Proxmox storage definition, user and group management, and service setup (like Samba).

## Getting Started

These instructions will guide you through preparing your Proxmox host and executing the automation scripts.

### Prerequisites

1.  **Fresh Proxmox VE Installation:** Start with a clean installation of Proxmox VE (tested with version 8.x). The target system should have at least 3 NVMe SSDs for the intended ZFS configuration.
2.  **Root Access:** You must have root (`sudo su -` or direct root login) access to the Proxmox host to execute these scripts.
3.  **Internet Connection:** The host needs internet access during the setup process to download packages and updates.
4.  **SSH Key (Optional but Recommended):** Have your public SSH key ready if you intend to add it to the new admin user account.

### Installation

1.  **Download the Scripts:**
    Download and extract the latest release of the Phoenix scripts to the Proxmox host. You can do this directly on the host using `wget` and `tar`.

    ```bash
    # Download the release archive (replace vX.XX.XX with the desired version if different)
    wget https://github.com/SirHeads/phoenix-scripts/archive/refs/tags/v0.09.10.tar.gz

    # Extract the archive
    tar -xzf v0.09.10.tar.gz

    # Navigate into the extracted directory
    cd phoenix-scripts-0.09.10
    ```

2.  **Install the Scripts:**
    Copy the script files to the designated location (`/usr/local/bin`) and ensure they are executable.

    ```bash
    # Copy scripts to /usr/local/bin (requires root)
    sudo cp *.sh /usr/local/bin/

    # Make the scripts executable (requires root)
    sudo chmod +x /usr/local/bin/*.sh
    ```

3.  **Run the Orchestrator Script:**
    Execute the main orchestrator script. It will prompt you for necessary configuration details like admin user credentials, SMB password, drive selections, and network settings.

    ```bash
    # Run the main setup script (requires root)
    sudo /usr/local/bin/create_phoenix.sh
    ```

    **Follow the on-screen prompts carefully.**

## Script Details

Here's a breakdown of the key scripts involved in the Phoenix setup process:

*   **`create_phoenix.sh` (Orchestrator):**
    The main script that coordinates the entire setup. It sources configuration and common functions, validates root privileges, prompts for user input (admin credentials, drive selection, network config), validates selected drives, and executes the subsequent setup scripts in the correct order. It uses a state file (`/tmp/phoenix_setup_state`) to track completed steps, allowing potential resumption or reruns by skipping already successful stages. It also handles logging the overall process.

*   **`phoenix_config.sh` (Configuration):**
    Defines global variables and configurations used across the scripts. This includes:
    *   ZFS pool names (`quickOS`, `fastData`).
    *   Lists of ZFS datasets to create within each pool (`QUICKOS_DATASET_LIST`, `FASTDATA_DATASET_LIST`).
    *   Associative arrays defining ZFS properties (like `compression`, `recordsize`, `sync`, `quota`, `atime`) for each dataset (`QUICKOS_DATASET_PROPERTIES`, `FASTDATA_DATASET_PROPERTIES`).
    *   Mappings between datasets and their intended Proxmox storage types/IDs (`DATASET_STORAGE_TYPES`).
    *   The default SMB user name (`SMB_USER`).
    *   (NFS configuration is present but largely disabled for the 3-drive setup).

*   **`common.sh` (Shared Functions):**
    Contains reusable functions used by multiple setup scripts to perform common tasks and maintain consistency. Key functions include:
    *   Logging setup (`setup_logging`).
    *   Root user checks (`check_root`).
    *   Package installation checks (`check_package`).
    *   Network interface validation (`check_interface_in_subnet`).
    *   ZFS pool/dataset creation and property setting (`create_zfs_pool`, `create_zfs_dataset`, `set_zfs_properties`).
    *   NFS export configuration (`configure_nfs_export`).
    *   Command execution with retry logic (`retry_command`).
    *   User and group management helpers (`create_system_user`, `add_user_to_groups`).

*   **`phoenix_proxmox_initial_setup.sh` (Initial OS Setup):**
    Performs fundamental OS-level configurations and installations:
    *   Disables Proxmox subscription repositories and adds no-subscription repos.
    *   Performs a full `apt update` and `dist-upgrade`.
    *   Installs essential tools (`s-tui`, `ufw`, `chrony`, `Samba`).
    *   Prompts for and sets the hostname and static network configuration (IP, Gateway, Interface, DNS).
    *   Configures the `ufw` firewall to allow necessary services (SSH, Proxmox UI on 8006/tcp, NFS, Samba).
    *   Sets the system timezone (default: America/New_York) and configures NTP using `chrony`.
    *   Sets up log rotation for the setup log file.

*   **`phoenix_install_nvidia_driver.sh` (NVIDIA Driver Installation):**
    Handles the installation of NVIDIA GPU drivers using the official NVIDIA runfile installer:
    *   Downloads the specified NVIDIA driver version (e.g., 535.129.03).
    *   Disables the open-source Nouveau driver.
    *   Stops the display manager.
    *   Runs the NVIDIA installer in silent mode.
    *   Regenerates the initramfs to ensure the new driver is loaded on boot.

*   **`phoenix_create_admin_user.sh` (Admin User Creation):**
    Creates a non-root administrative user account:
    *   Takes username, password, and an optional SSH public key as arguments (though typically called by the orchestrator which provides these).
    *   Creates the user with a home directory (`/home/<username>`) and `/bin/bash` shell.
    *   Adds the user to privileged groups (`sudo`, `adm`, `wheel`).
    *   Sets the specified password for the user.
    *   If an SSH key is provided, it creates the user's `~/.ssh` directory, sets appropriate permissions, and adds the key to `~/.ssh/authorized_keys`.
    *   Optionally creates a corresponding user within Proxmox VE (`<username>@pve`) and sets its password.

*   **`phoenix_setup_zfs_pools.sh` (ZFS Pool Creation):**
    Creates the ZFS storage pools based on the configuration and user-selected drives:
    *   For the 3-drive setup: Creates a mirrored `quickOS` pool using two drives and a single-drive `fastData` pool using the third.
    *   Handles drive validation and ensures selected drives are not currently in use by existing ZFS pools or contain existing filesystems/partitions.
    *   Uses the validated drive paths passed from the orchestrator.

*   **`phoenix_setup_zfs_datasets.sh` (ZFS Dataset Creation):**
    Creates the predefined ZFS datasets within the `quickOS` and `fastData` pools as specified in `phoenix_config.sh`:
    *   Iterates through the dataset lists (`QUICKOS_DATASET_LIST`, `FASTDATA_DATASET_LIST`).
    *   Creates each dataset under its respective pool.
    *   Applies the defined ZFS properties (`compression`, `recordsize`, etc.) to each dataset using the `set_zfs_properties` function from `common.sh`.

*   **`phoenix_create_storage.sh` (Proxmox Storage Integration):**
    Integrates the created ZFS datasets and directories into Proxmox VE as storage definitions:
    *   Reads the `DATASET_STORAGE_TYPES` mapping from `phoenix_config.sh`.
    *   Determines if a dataset should be added as a ZFS Pool storage (`zfspool:images/rootdir`) or Directory storage (`dir:backup,iso,images,vztmpl`) in Proxmox.
    *   Uses `pvesm add` to create the storage entries in Proxmox, linking them to the actual ZFS paths or mountpoints.
    *   Assigns appropriate content types (`images`, `backup`, `iso`, `rootdir`, `vztmpl`) based on the configuration.

*   **`phoenix_setup_nfs.sh` (NFS Server Configuration - Partially Disabled):**
    Configures the host to act as an NFS server:
    *   Installs required NFS packages (`nfs-kernel-server`).
    *   Configures the firewall (`ufw`) to allow NFS traffic.
    *   While the script framework is present and runs, the actual creation of NFS export datasets is disabled in the current `phoenix_config.sh` for the 3-drive setup. The datasets intended for NFS (`shared-prod-data`, `shared-prod-data-sync`, `shared-test-data`, `shared-bulk-data`) are instead created as local ZFS datasets within `quickOS` or `fastData` pools. The script skips configuring exports for non-existent pools/datasets.
    *   (If enabled) It would configure `/etc/exports`, restart the NFS service, and potentially add the NFS shares as storage within Proxmox.

*   **`phoenix_setup_samba.sh` (Samba Server Configuration):**
    Configures the Samba service to share specific local ZFS datasets created under `fastData` and `quickOS`:
    *   Creates the SMB user account (default: `smbuser`).
    *   Prompts for and sets the SMB password.
    *   Configures the `/etc/samba/smb.conf` file with share definitions for datasets like `shared-backups`, `shared-iso`, `shared-test-data`, `shared-bulk-data`, `shared-prod-data`, and `shared-prod-data-sync`, applying appropriate permissions and settings.
    *   Restarts the Samba services (`smbd`, `nmbd`) to apply the configuration.

## Contributing

Contributions to improve the scripts or documentation are welcome. Please fork the repository and submit a pull request.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/SirHeads/phoenix-scripts/tags).

## Authors

*   **Heads**
*   **Grok**
*   **Devstral**
*   **Qwen3-coder**

See also the list of [contributors](https://github.com/SirHeads/phoenix-scripts/contributors) who participated in this project.

## License

Specify your license here. For example: `GPL-3.0`. Please add a `LICENSE` file to your repository if you choose a specific license.