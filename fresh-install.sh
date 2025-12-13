#!/bin/bash

# Bootstrap script to setup a fresh system and restore docker-compose services
# 
# USAGE:
#   This script must be run with sudo on a fresh system installation
#
# PREREQUISITES:
#   - Backup drive with repository at /mnt/SSD/Backup/NVME/compose
#   - Disk UUIDs configured in the script matching your system
#
# EXECUTION:
#   Method 1 - Download and execute from GitHub (recommended for fresh installs):
#     curl -fsSL https://raw.githubusercontent.com/premorion/atticserver-docker-compose/main/scripts/fresh-install.sh | sudo bash
#     
#     # Or using wget:
#     wget -qO- https://raw.githubusercontent.com/premorion/atticserver-docker-compose/main/scripts/fresh-install.sh | sudo bash
#
#   Method 2 - Direct execution (if you have the script locally):
#     sudo bash fresh-install.sh
#
#   Method 3 - From backup drive (if already mounted):
#     sudo bash /mnt/SSD/Backup/NVME/compose/scripts/fresh-install.sh
#
# WHAT IT DOES:
#   1. Detects system type (Bazzite/Fedora Atomic/Ubuntu/Fedora)
#   2. Installs essential packages (git, rsync, curl, wget, vim, zsh, ethtool, etc.)
#   3. Installs Oh My Zsh and zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)
#   4. Installs Docker CE and adds user to docker group
#   5. Configures fstab entries and mounts disks (DATOS1, DATOS, SSD)
#   6. Copies repository from backup to /opt/docker/compose (if not exists) or pulls updates
#   7. Restores system configuration files (.zshrc, .zsh_history, .oh-my-zsh)
#   8. Configures git user (email and name) for the actual user
#   9. Generates SSH key for Gitea and configures SSH config
#   10. Initializes Git repository with remote origin
#   11. Starts docker-compose services (excluding enshrouded and palworld)
#
# IDEMPOTENCY:
#   - Script can be run multiple times safely
#   - Only installs/configures what is missing
#   - Skips already completed steps
#   - Useful for resuming after interruptions or reboots
#
# NOTES FOR BAZZITE/FEDORA ATOMIC:
#   - First run will install packages and REQUIRES a reboot
#   - After reboot, run this script again to continue
#   - Docker installation requires a reboot to take effect
#   - System uses rpm-ostree (immutable filesystem)
#
# LOGS:
#   - Logs are saved to: /home/<user>/temp/logs/fresh-install-<date>.log
#   - Old logs (>20 days) are automatically cleaned up
#
# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo"
  exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

# Define log variables
LOG_FOLDER=/home/$ACTUAL_USER/temp/logs
LOG_DATE=$(date +'%m%d%Y')
RESTORE_LOG_FILENAME=fresh-install-$LOG_DATE.log
RESTORE_LOG_FILE="$LOG_FOLDER/$RESTORE_LOG_FILENAME"
RESTORE_DEST=/opt/docker/compose

# Create log folder
[ -d $LOG_FOLDER ] || mkdir -p $LOG_FOLDER
chown -R $ACTUAL_USER:$ACTUAL_USER $LOG_FOLDER

echo "$(tput setaf 3)Bootstrap: Starting setup process...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE

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
  
  # Enable Wake-on-LAN for eno1 interface
  echo "$(tput setaf 3)Configuring Wake-on-LAN...$(tput sgr0)"
  if nmcli c show "eno1" &> /dev/null; then
    nmcli c modify "eno1" 802-3-ethernet.wake-on-lan magic
    echo "Wake-on-LAN enabled for eno1"
  else
    echo "$(tput setaf 1)Warning: Network connection 'eno1' not found, skipping WoL configuration$(tput sgr0)"
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
  echo "Docker already installed" | tee -a $RESTORE_LOG_FILE
  
  # Ensure Docker service is running
  if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..." | tee -a $RESTORE_LOG_FILE
    systemctl start docker
    systemctl enable docker
  fi
  
  # Add user to docker group if not already
  if ! id $ACTUAL_USER | grep -q '\bdocker\b'; then
    # For Bazzite/Atomic systems, ensure docker group exists in /etc/group
    if [ "$SYSTEM_TYPE" = "atomic" ]; then
      echo "Configuring docker group for atomic system..." | tee -a $RESTORE_LOG_FILE
      
      # Check if docker group exists in /etc/group
      if ! grep -q "^docker:" /etc/group; then
        # Get the docker GID from the system
        DOCKER_GID=$(getent group docker | cut -d: -f3)
        if [ -z "$DOCKER_GID" ]; then
          DOCKER_GID=955
        fi
        echo "docker:x:$DOCKER_GID:$ACTUAL_USER" >> /etc/group
        echo "Created docker group in /etc/group with user $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
      else
        # Group exists, add user to it
        sed -i "/^docker:/s/$/,$ACTUAL_USER/" /etc/group
        sed -i 's/:,/:/' /etc/group  # Clean up if there's a leading comma
        echo "Added $ACTUAL_USER to existing docker group in /etc/group" | tee -a $RESTORE_LOG_FILE
      fi
      
      # Create docker socket override directory
      mkdir -p /etc/systemd/system/docker.socket.d
      
      # Create override file to set socket permissions
      cat > /etc/systemd/system/docker.socket.d/override.conf << 'DOCKEREOF'
[Socket]
SocketMode=0666
DOCKEREOF
      
      # Reload systemd and restart docker socket
      systemctl daemon-reload
      systemctl restart docker.socket
      systemctl restart docker.service
      
      echo "Docker configured for atomic system - socket is now world-writable" | tee -a $RESTORE_LOG_FILE
      echo "$(tput setaf 3)Note: You can now use docker without sudo, but you may need to logout/login first$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
    else
      # Standard systems
      usermod -aG docker $ACTUAL_USER
      echo "User $ACTUAL_USER added to docker group" | tee -a $RESTORE_LOG_FILE
    fi
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
  
  # Step 1: Configure fstab and mount disks
  echo "$(tput setaf 3)Configuring disk mounts...$(tput sgr0)"
  
  # Define fstab entries
  FSTAB_ENTRIES=(
    "UUID=abce8dd5-ff05-474d-ba08-8d5524ce587d /mnt/DATOS1   ext4 defaults 0 0"
    "UUID=c8d82fc0-27f8-4f05-ac2f-e591861e014d /mnt/DATOS    ext4 defaults 0 0"
    "UUID=7572de5b-befb-4b46-a9c2-fb08e8a938ee /mnt/SSD      ext4 defaults 0 0"
  )
  
  # Step 2: Process fstab entries to create mount points and mount drives
  echo "$(tput setaf 2)Processing fstab entries and mounting drives...$(tput sgr0)"
  
  for line in "${FSTAB_ENTRIES[@]}"; do
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
  done
  
  # Reload and mount all filesystems
  systemctl daemon-reload
  mount -a
  
  echo "$(tput setaf 2)Filesystems mounted$(tput sgr0)"
  
  # Verify backup is accessible
  if [ ! -d "/mnt/SSD/Backup/NVME/compose" ]; then
    echo "$(tput setaf 1)Error: Backup not accessible at /mnt/SSD/Backup/NVME/compose$(tput sgr0)"
    echo "$(tput setaf 3)Please verify the backup drive is mounted correctly$(tput sgr0)"
    echo ""
    echo "Available block devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID
    exit 1
  fi
  
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

# Check if user needs to re-login for docker group
if groups $ACTUAL_USER | grep -q '\bdocker\b'; then
  # User is in docker group, check if current session has the group active
  if ! groups | grep -q '\bdocker\b' 2>/dev/null && [ ! -z "$SUDO_USER" ]; then
    echo ""
    echo "$(tput setaf 1)IMPORTANT: User added to docker group$(tput sgr0)"
    echo "$(tput setaf 3)You need to log out and log back in for docker permissions to take effect$(tput sgr0)"
    echo "$(tput setaf 3)After re-login, run attic-restore.sh manually:$(tput sgr0)"
    echo "  sudo bash /opt/docker/compose/scripts/attic-restore.sh"
    echo ""
    exit 0
  fi
fi

# Verify .env files were restored
ENV_COUNT_BACKUP=$(find /mnt/SSD/Backup/NVME/compose -name ".env" -type f | wc -l)
ENV_COUNT_RESTORED=$(find /opt/docker/compose -name ".env" -type f 2>/dev/null | wc -l)
echo "✓ .env files restored: $ENV_COUNT_RESTORED / $ENV_COUNT_BACKUP" | tee -a $RESTORE_LOG_FILE

# Fix permissions for container directories
echo "Fixing permissions for container directories..." | tee -a $RESTORE_LOG_FILE
if [ -d "$RESTORE_DEST/services/containers" ]; then
  ACTUAL_UID=$(id -u $ACTUAL_USER)
  ACTUAL_GID=$(id -g $ACTUAL_USER)
  chown -R $ACTUAL_UID:$ACTUAL_GID $RESTORE_DEST/services/containers 2>&1 | tee -a $RESTORE_LOG_FILE
  chmod -R 755 $RESTORE_DEST/services/containers 2>&1 | tee -a $RESTORE_LOG_FILE
  echo "Permissions fixed: owner=$ACTUAL_UID:$ACTUAL_GID, mode=755" | tee -a $RESTORE_LOG_FILE
fi

# Verify critical databases were restored
echo "Verifying critical files were restored..." | tee -a $RESTORE_LOG_FILE
for db_path in "services/containers/sonarr/config/sonarr.db" "services/containers/radarr/config/radarr.db" "services/containers/plex/config/Library"; do
  if [ -e "$RESTORE_DEST/$db_path" ]; then
    echo "✓ Found: $db_path" | tee -a $RESTORE_LOG_FILE
  else
    echo "⚠ Missing: $db_path" | tee -a $RESTORE_LOG_FILE
  fi
done

echo "###(DONE) Restore complete compose folder###" | tee -a $RESTORE_LOG_FILE

echo "###(IN PROGRESS) Restore system configuration files###" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 2)Restoring system configuration files$(tput sgr0)"

# Restore .oh-my-zsh directory first (if exists in backup)
if [ -d "/mnt/SSD/Backup/NVME/compose/scripts/server-utils/.oh-my-zsh" ]; then
  echo "$(tput setaf 3)Restoring .oh-my-zsh directory...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  rsync -a --out-format="%n" /mnt/SSD/Backup/NVME/compose/scripts/server-utils/.oh-my-zsh/ $ACTUAL_HOME/.oh-my-zsh/ 2>&1 | tee -a $RESTORE_LOG_FILE
  chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.oh-my-zsh
  echo ".oh-my-zsh directory restored for $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
else
  echo "Warning: .oh-my-zsh not found in backup, will install plugins manually" | tee -a $RESTORE_LOG_FILE
fi

# Restore .zshrc for user
if [ -f "/mnt/SSD/Backup/NVME/compose/scripts/server-utils/.zshrc" ]; then
  cp /mnt/SSD/Backup/NVME/compose/scripts/server-utils/.zshrc $ACTUAL_HOME/.zshrc 2>&1 | tee -a $RESTORE_LOG_FILE
  chown $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.zshrc
  echo ".zshrc restored for $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
else
  echo "Warning: .zshrc not found in backup" | tee -a $RESTORE_LOG_FILE
fi

# Restore .zsh_history for user
if [ -f "/mnt/SSD/Backup/NVME/compose/scripts/server-utils/.zsh_history" ]; then
  cp /mnt/SSD/Backup/NVME/compose/scripts/server-utils/.zsh_history $ACTUAL_HOME/.zsh_history 2>&1 | tee -a $RESTORE_LOG_FILE
  chown $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.zsh_history
  echo ".zsh_history restored for $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
else
  echo "Warning: .zsh_history not found in backup" | tee -a $RESTORE_LOG_FILE
fi

# Install zsh plugins if Oh My Zsh is present but plugins are missing
if [ -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  echo "$(tput setaf 3)Checking zsh plugins...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  
  # Install zsh-autosuggestions
  if [ ! -d "$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..." | tee -a $RESTORE_LOG_FILE
    git clone https://github.com/zsh-users/zsh-autosuggestions $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions 2>&1 | tee -a $RESTORE_LOG_FILE
    chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    echo "zsh-autosuggestions installed" | tee -a $RESTORE_LOG_FILE
  else
    echo "zsh-autosuggestions already present" | tee -a $RESTORE_LOG_FILE
  fi
  
  # Install zsh-syntax-highlighting
  if [ ! -d "$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..." | tee -a $RESTORE_LOG_FILE
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting 2>&1 | tee -a $RESTORE_LOG_FILE
    chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    echo "zsh-syntax-highlighting installed" | tee -a $RESTORE_LOG_FILE
  else
    echo "zsh-syntax-highlighting already present" | tee -a $RESTORE_LOG_FILE
  fi
fi

# Change default shell to zsh if not already set
CURRENT_SHELL=$(getent passwd $ACTUAL_USER | cut -d: -f7)
if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ] && [ "$CURRENT_SHELL" != "/bin/zsh" ]; then
  echo "$(tput setaf 3)Changing default shell to zsh for $ACTUAL_USER...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  usermod -s /usr/bin/zsh $ACTUAL_USER 2>&1 | tee -a $RESTORE_LOG_FILE
  if [ $? -eq 0 ]; then
    echo "Default shell changed to zsh for $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
  else
    echo "Warning: Failed to change default shell to zsh" | tee -a $RESTORE_LOG_FILE
  fi
else
  echo "Default shell is already zsh for $ACTUAL_USER" | tee -a $RESTORE_LOG_FILE
fi

echo "###(DONE) Restore system configuration files###" | tee -a $RESTORE_LOG_FILE

echo "###(IN PROGRESS) Configure Git###" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 2)Configuring Git user information$(tput sgr0)"
sudo -u $ACTUAL_USER git config --global user.email "premorion@gmail.com" 2>&1 | tee -a $RESTORE_LOG_FILE
sudo -u $ACTUAL_USER git config --global user.name "Pedro MP" 2>&1 | tee -a $RESTORE_LOG_FILE
echo "Git configured with user: Pedro MP <premorion@gmail.com>" | tee -a $RESTORE_LOG_FILE
echo "###(DONE) Configure Git###" | tee -a $RESTORE_LOG_FILE

echo "###(IN PROGRESS) Setup SSH key and clone repository###" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 2)Setting up SSH key for git repository$(tput sgr0)"

# Generate SSH key if it doesn't exist
SSH_KEY_PATH="$ACTUAL_HOME/.ssh/id_ed25519_gitea"
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "Generating SSH key for Gitea repository..." | tee -a $RESTORE_LOG_FILE
  sudo -u $ACTUAL_USER ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "gitea-atticserver" 2>&1 | tee -a $RESTORE_LOG_FILE
  echo "SSH key generated at $SSH_KEY_PATH" | tee -a $RESTORE_LOG_FILE
else
  echo "SSH key already exists at $SSH_KEY_PATH" | tee -a $RESTORE_LOG_FILE
fi

# Display the public key
echo "" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 3)========================================$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 3)SSH Public Key:$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 6)$(cat ${SSH_KEY_PATH}.pub)$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 3)========================================$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 3)Please add this SSH key to your Gitea repository at:$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "$(tput setaf 6)http://192.168.2.102:222/user/settings/keys$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
echo "" | tee -a $RESTORE_LOG_FILE

# Wait for user confirmation
read -p "$(tput setaf 3)Press ENTER once you have added the SSH key to Gitea...$(tput sgr0) " -r

# Configure SSH for custom port and known host
mkdir -p "$ACTUAL_HOME/.ssh"
SSH_CONFIG="$ACTUAL_HOME/.ssh/config"

# Add SSH config for Gitea if not already present
if ! grep -q "Host gitea-atticserver" "$SSH_CONFIG" 2>/dev/null; then
  echo "Configuring SSH for Gitea repository..." | tee -a $RESTORE_LOG_FILE
  cat >> "$SSH_CONFIG" << 'EOF'

Host gitea-atticserver
    HostName 192.168.2.102
    Port 222
    User git
    IdentityFile ~/.ssh/id_ed25519_gitea
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
  chown $ACTUAL_USER:$ACTUAL_USER "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  echo "SSH config updated" | tee -a $RESTORE_LOG_FILE
fi

# Initialize Git repository if copied from backup
if [ -d "/opt/docker/compose/.git" ]; then
  echo "$(tput setaf 3)Initializing Git repository...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  cd /opt/docker/compose
  
  # Remove remote if it exists and re-add it
  sudo -u $ACTUAL_USER git remote remove origin 2>/dev/null || true
  sudo -u $ACTUAL_USER git remote add origin ssh://gitea-atticserver/premorion/atticserver-docker-compose.git 2>&1 | tee -a $RESTORE_LOG_FILE
  
  echo "Git repository initialized" | tee -a $RESTORE_LOG_FILE
fi

echo "###(DONE) Setup SSH key and clone repository###" | tee -a $RESTORE_LOG_FILE

# Ensure Docker is running before starting containers
if ! systemctl is-active --quiet docker; then
  echo "$(tput setaf 1)Docker service is not running. Starting it now...$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  systemctl start docker
  sleep 5
fi

echo "$(tput setaf 2)Starting containers from docker-compose services$(tput sgr0)"
echo "###(IN PROGRESS) Start containers - docker-compose up###" | tee -a $RESTORE_LOG_FILE
cd /opt/docker/compose

if [ -f "docker-compose.yml" ]; then
  docker compose -f docker-compose.yml up -d --remove-orphans 2>&1 | tee -a $RESTORE_LOG_FILE
  docker compose stop enshrouded palworld 2>&1 | tee -a $RESTORE_LOG_FILE
  echo "###(DONE) Start containers - docker-compose up###" | tee -a $RESTORE_LOG_FILE
else
  echo "$(tput setaf 1)Error: docker-compose.yml not found$(tput sgr0)" | tee -a $RESTORE_LOG_FILE
  exit 1
fi

echo ""
echo "$(tput setaf 2)========================================$(tput sgr0)"
echo "$(tput setaf 2)Fresh installation completed successfully!$(tput sgr0)"
echo "$(tput setaf 2)========================================$(tput sgr0)"
echo "" 
echo "Logs saved to: $RESTORE_LOG_FILE"
echo ""
echo "$(tput setaf 3)IMPORTANT:$(tput sgr0)"
echo "- If you were added to the docker group, you may need to log out and back in"
echo "- Check the containers are running: docker ps"
echo "- Review logs if needed: $RESTORE_LOG_FILE"
echo ""
