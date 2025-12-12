#!/bin/bash

# Bootstrap script to setup a fresh system and restore docker-compose services
# 
# USAGE:
#   This script must be run with sudo on a fresh system installation
#
# PREREQUISITES:
#   - Backup drive with repository at /mnt/SSD/Backup/NVME/compose (will be auto-detected)
#   - OR the backup drive mounted manually before running
#
# EXECUTION:
#   Method 1 - Download and execute from GitHub (recommended for fresh installs):
#     curl -fsSL https://raw.githubusercontent.com/premorion/atticserver-docker-compose/main/scripts/bootstrap.sh | sudo bash
#     
#     # Or using wget:
#     wget -qO- https://raw.githubusercontent.com/premorion/atticserver-docker-compose/main/scripts/bootstrap.sh | sudo bash
#
#   Method 2 - Direct execution (if you have the script locally):
#     sudo bash bootstrap.sh
#
#   Method 3 - From backup drive (if already mounted):
#     sudo bash /mnt/SSD/Backup/NVME/compose/scripts/bootstrap.sh
#
# WHAT IT DOES:
#   1. Detects system type (Bazzite/Ubuntu/Fedora)
#   2. Installs essential packages (git, rsync, curl, wget, vim, zsh, etc.)
#   3. Installs Oh My Zsh
#   4. Installs Docker CE
#   5. Searches for and mounts backup drive automatically
#   6. Copies repository from backup to /opt/docker/compose
#   7. Runs cluster-restore.sh to restore all services and data
#
# NOTES FOR BAZZITE:
#   - First run will install packages and may require a reboot
#   - After reboot, run this script again to continue
#   - Docker installation requires a reboot to take effect
#
# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo"
  exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

echo "$(tput setaf 3)Bootstrap: Starting setup process...$(tput sgr0)"

# Detect package manager and install essential packages
if command -v rpm-ostree &> /dev/null; then
  # Bazzite/Fedora Atomic - immutable system
  echo "$(tput setaf 3)Detected immutable system (Bazzite/Fedora Atomic)$(tput sgr0)"
  PKG_MANAGER="rpm-ostree"
  
  # Check if git and rsync are already installed
  if ! command -v git &> /dev/null || ! command -v rsync &> /dev/null; then
    echo "$(tput setaf 2)Installing essential packages with rpm-ostree...$(tput sgr0)"
    rpm-ostree install git rsync
    echo "$(tput setaf 1)IMPORTANT: System needs to reboot to apply changes$(tput sgr0)"
    echo "After reboot, run this script again to continue."
    read -p "Reboot now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      systemctl reboot
    else
      echo "Please reboot manually and run this script again."
      exit 0
    fi
  fi
elif command -v apt &> /dev/null; then
  # Debian/Ubuntu based
  echo "$(tput setaf 3)Detected Debian/Ubuntu based system$(tput sgr0)"
  PKG_MANAGER="apt"
  
  if ! command -v git &> /dev/null || ! command -v rsync &> /dev/null; then
    echo "$(tput setaf 2)Installing essential packages...$(tput sgr0)"
    apt update
    apt install -y git rsync
  fi
elif command -v dnf &> /dev/null; then
  # Fedora/RHEL
  echo "$(tput setaf 3)Detected Fedora/RHEL based system$(tput sgr0)"
  PKG_MANAGER="dnf"
  
  if ! command -v git &> /dev/null || ! command -v rsync &> /dev/null; then
    echo "$(tput setaf 2)Installing essential packages...$(tput sgr0)"
    dnf install -y git rsync
  fi
else
  echo "$(tput setaf 1)Warning: Unknown package manager$(tput sgr0)"
  if ! command -v git &> /dev/null || ! command -v rsync &> /dev/null; then
    echo "$(tput setaf 1)Error: git and/or rsync not found. Please install them manually.$(tput sgr0)"
    exit 1
  fi
fi

echo "$(tput setaf 2)Essential packages are available$(tput sgr0)"

# Detect system type for later use
if command -v rpm-ostree &> /dev/null; then
  SYSTEM_TYPE="atomic"
elif command -v apt &> /dev/null; then
  SYSTEM_TYPE="debian"
elif command -v dnf &> /dev/null; then
  SYSTEM_TYPE="fedora"
else
  SYSTEM_TYPE="unknown"
fi

echo "$(tput setaf 3)Installing system dependencies...$(tput sgr0)"

# Install additional system packages
if [ "$SYSTEM_TYPE" = "atomic" ]; then
  # Check if packages need to be installed
  PACKAGES_NEEDED=()
  
  for pkg in curl wget vim ethtool zsh; do
    if ! command -v $pkg &> /dev/null 2>&1 && ! rpm -q $pkg &> /dev/null 2>&1; then
      PACKAGES_NEEDED+=($pkg)
    fi
  done
  
  if [ ${#PACKAGES_NEEDED[@]} -gt 0 ]; then
    echo "Installing packages: ${PACKAGES_NEEDED[*]}"
    rpm-ostree install ${PACKAGES_NEEDED[*]}
    echo "$(tput setaf 1)IMPORTANT: System needs to reboot to apply package changes$(tput sgr0)"
    echo "After reboot, run this script again to continue."
    read -p "Reboot now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      systemctl reboot
    else
      echo "Please reboot manually and run this script again."
      exit 0
    fi
  fi
  
elif [ "$SYSTEM_TYPE" = "debian" ]; then
  apt install -y curl wget vim nano ca-certificates gnupg lsb-release ethtool
  
  # Install zsh
  if ! command -v zsh &> /dev/null; then
    apt install -y zsh
    chsh -s $(which zsh) $ACTUAL_USER
    echo "zsh installed and set as default shell"
  fi
  
elif [ "$SYSTEM_TYPE" = "fedora" ]; then
  dnf install -y curl wget vim nano ca-certificates gnupg ethtool zsh
  
  # Set zsh as default shell
  if command -v zsh &> /dev/null; then
    chsh -s $(which zsh) $ACTUAL_USER
    echo "zsh set as default shell"
  fi
fi

# Install Oh My Zsh if not present
if [ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  echo "$(tput setaf 3)Installing Oh My Zsh...$(tput sgr0)"
  su - $ACTUAL_USER -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
  echo "Oh My Zsh installed"
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
  echo "$(tput setaf 3)Installing Docker...$(tput sgr0)"
  
  if [ "$SYSTEM_TYPE" = "atomic" ]; then
    echo "Installing Docker on Bazzite/Atomic system using rpm-ostree..."
    
    # Add Docker CE repository
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
    
    # Install Docker using rpm-ostree
    rpm-ostree install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    if [ $? -eq 0 ]; then
      echo "$(tput setaf 1)IMPORTANT: System needs to reboot to apply Docker installation$(tput sgr0)"
      echo "After reboot, run this script again to continue."
      
      # Enable docker service for next boot
      systemctl enable docker || true
      
      read -p "Reboot now? (y/n): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl reboot
      else
        echo "Please reboot manually and run this script again."
        exit 0
      fi
    else
      echo "$(tput setaf 1)Error: Failed to install Docker$(tput sgr0)"
      exit 1
    fi
    
  elif [ "$SYSTEM_TYPE" = "debian" ]; then
    # Remove old Docker installations
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    # Add user to docker group
    usermod -aG docker $ACTUAL_USER
    
    echo "Docker installed and enabled"
    
  elif [ "$SYSTEM_TYPE" = "fedora" ]; then
    # Install Docker on Fedora
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    # Add user to docker group
    usermod -aG docker $ACTUAL_USER
    
    echo "Docker installed and enabled"
  fi
else
  echo "Docker already installed"
  
  # Make sure Docker is enabled and started
  systemctl enable docker || true
  systemctl start docker || true
  
  # Add user to docker group if not already
  if ! groups $ACTUAL_USER | grep -q '\bdocker\b'; then
    usermod -aG docker $ACTUAL_USER
    echo "User $ACTUAL_USER added to docker group"
  fi
fi

echo "$(tput setaf 2)System dependencies installed$(tput sgr0)"

# Check if repository already exists
if [ -d "/opt/docker/compose/.git" ]; then
  echo "$(tput setaf 3)Repository already exists at /opt/docker/compose$(tput sgr0)"
  echo "$(tput setaf 2)Pulling latest changes...$(tput sgr0)"
  cd /opt/docker/compose
  su - $ACTUAL_USER -c "cd /opt/docker/compose && git pull" || true
  chown -R $ACTUAL_USER:$ACTUAL_USER /opt/docker/compose
else
  echo "$(tput setaf 2)Repository not found. Starting recovery process...$(tput sgr0)"
  
  # Step 1: Try to mount backup drive using fstab from a temporary location
  TEMP_FSTAB="/tmp/fstab.backup"
  
  # Check if we can access any backup location to get fstab
  if [ -f "/mnt/SSD/Backup/NVME/compose/scripts/server-utils/fstab" ]; then
    FSTAB_SOURCE="/mnt/SSD/Backup/NVME/compose/scripts/server-utils/fstab"
  else
    echo "$(tput setaf 3)Backup drive not mounted. Attempting to mount...$(tput sgr0)"
    
    # Try to find and mount the SSD backup drive
    # First, check if UUID is in current fstab
    if grep -q "/mnt/SSD" /etc/fstab 2>/dev/null; then
      echo "$(tput setaf 2)Found SSD entry in /etc/fstab, attempting to mount...$(tput sgr0)"
      mkdir -p /mnt/SSD
      mount /mnt/SSD 2>/dev/null || true
    else
      # Try to find the backup drive by looking for the backup directory structure
      echo "$(tput setaf 3)Searching for backup drive...$(tput sgr0)"
      
      BACKUP_FOUND=false
      
      # List all block devices and try to find the one with the backup
      for device in $(lsblk -nrpo NAME,TYPE | awk '$2=="part" {print $1}'); do
        # Skip if already mounted
        if mountpoint -q /mnt/SSD 2>/dev/null; then
          break
        fi
        
        echo "Checking $device..."
        
        # Try to mount temporarily
        mkdir -p /mnt/temp_check
        if mount -o ro "$device" /mnt/temp_check 2>/dev/null; then
          # Check if this has the backup structure
          if [ -d "/mnt/temp_check/Backup/NVME/compose" ]; then
            echo "$(tput setaf 2)Found backup on $device$(tput sgr0)"
            
            # Get UUID of this device
            DEVICE_UUID=$(blkid -s UUID -o value "$device")
            
            if [ ! -z "$DEVICE_UUID" ]; then
              echo "Device UUID: $DEVICE_UUID"
              
              # Unmount temporary mount
              umount /mnt/temp_check
              
              # Mount to proper location
              mkdir -p /mnt/SSD
              mount UUID="$DEVICE_UUID" /mnt/SSD
              
              if [ $? -eq 0 ]; then
                echo "$(tput setaf 2)Successfully mounted backup drive to /mnt/SSD$(tput sgr0)"
                
                # Add to fstab for future boots
                if ! grep -q "UUID=$DEVICE_UUID" /etc/fstab 2>/dev/null; then
                  FSTYPE=$(blkid -s TYPE -o value "$device")
                  echo "UUID=$DEVICE_UUID /mnt/SSD $FSTYPE defaults 0 2" >> /etc/fstab
                  echo "Added backup drive to /etc/fstab"
                fi
                
                BACKUP_FOUND=true
                break
              fi
            else
              umount /mnt/temp_check
            fi
          else
            umount /mnt/temp_check
          fi
        fi
      done
      
      # Clean up temp directory
      rmdir /mnt/temp_check 2>/dev/null || true
      
      if [ "$BACKUP_FOUND" = false ]; then
        echo "$(tput setaf 1)Error: Cannot find backup drive automatically$(tput sgr0)"
        echo "$(tput setaf 3)Please manually mount the backup drive at /mnt/SSD and run this script again$(tput sgr0)"
        echo ""
        echo "Available block devices:"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID
        echo ""
        echo "Example commands:"
        echo "  sudo mkdir -p /mnt/SSD"
        echo "  sudo mount /dev/sdX /mnt/SSD  # Replace sdX with your backup drive"
        echo "  # Or use UUID:"
        echo "  sudo mount UUID=your-uuid-here /mnt/SSD"
        exit 1
      fi
    fi
    
    # Check again if backup is now accessible
    if [ ! -f "/mnt/SSD/Backup/NVME/compose/scripts/server-utils/fstab" ]; then
      echo "$(tput setaf 1)Error: Backup not accessible at /mnt/SSD/Backup/NVME/compose$(tput sgr0)"
      echo "$(tput setaf 3)Please verify the backup drive is mounted correctly$(tput sgr0)"
      exit 1
    fi
    
    FSTAB_SOURCE="/mnt/SSD/Backup/NVME/compose/scripts/server-utils/fstab"
  fi
  
  # Step 2: Process fstab to create mount points and mount drives
  echo "$(tput setaf 2)Processing fstab and mounting drives...$(tput sgr0)"
  
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # Extract mount point (second field)
    mount_point=$(echo "$line" | awk '{print $2}')
    
    if [ ! -z "$mount_point" ]; then
      # Create mount point if it doesn't exist
      if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
        chown $ACTUAL_USER:$ACTUAL_USER "$mount_point"
        chmod 755 "$mount_point"
        echo "Created mount point: $mount_point"
      fi
      
      # Add to /etc/fstab if not already present
      if ! grep -qF "$line" /etc/fstab 2>/dev/null; then
        echo "$line" >> /etc/fstab
        echo "Added to fstab: $line"
      fi
    fi
  done < "$FSTAB_SOURCE"
  
  # Reload and mount all filesystems
  systemctl daemon-reload
  mount -a
  
  echo "$(tput setaf 2)Filesystems mounted$(tput sgr0)"
  
  # Step 3: Copy repository from backup
  if [ -d "/mnt/SSD/Backup/NVME/compose" ]; then
    echo "$(tput setaf 2)Copying repository from backup...$(tput sgr0)"
    
    mkdir -p /opt/docker
    rsync -a --info=progress2 /mnt/SSD/Backup/NVME/compose/ /opt/docker/compose/
    chown -R $ACTUAL_USER:$ACTUAL_USER /opt/docker/compose
    
    echo "$(tput setaf 2)Repository copied successfully from backup$(tput sgr0)"
  else
    echo "$(tput setaf 1)Error: Backup source not found at /mnt/SSD/Backup/NVME/compose$(tput sgr0)"
    exit 1
  fi
fi

# Make scripts executable
chmod +x /opt/docker/compose/scripts/*.sh

# Run cluster-restore
echo "$(tput setaf 2)Running cluster-restore.sh...$(tput sgr0)"
bash /opt/docker/compose/scripts/cluster-restore.sh
