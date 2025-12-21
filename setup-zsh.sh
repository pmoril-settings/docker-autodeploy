#!/bin/bash

# Standalone Zsh Setup Script
# 
# DESCRIPTION:
#   Installs and configures zsh with Oh My Zsh, plugins, LSD, and Atuin
#   Can be run on any system independently
#
# USAGE:
#   sudo bash setup-zsh.sh
#
# WHAT IT DOES:
#   1. Detects system type (Bazzite/Fedora Atomic/Ubuntu/Fedora)
#   2. Installs zsh
#   3. Installs Oh My Zsh
#   4. Installs zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)
#   5. Installs LSD (LSDeluxe) - modern ls replacement
#   6. Installs fzf - command-line fuzzy finder
#   7. Installs tldr - simplified man pages
#   8. Installs Atuin - magical shell history
#   9. Sets zsh as default shell
#
# IDEMPOTENCY:
#   - Script can be run multiple times safely
#   - Only installs/configures what is missing
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo"
  exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

echo "$(tput setaf 3)Zsh Setup: Starting configuration for user $ACTUAL_USER...$(tput sgr0)"

# Detect system type
if command -v rpm-ostree &> /dev/null; then
  SYSTEM_TYPE="atomic"
  echo "$(tput setaf 3)Detected immutable system (Bazzite/Fedora Atomic)$(tput sgr0)"
elif command -v apt &> /dev/null; then
  SYSTEM_TYPE="debian"
  echo "$(tput setaf 3)Detected Debian/Ubuntu based system$(tput sgr0)"
elif command -v dnf &> /dev/null; then
  SYSTEM_TYPE="fedora"
  echo "$(tput setaf 3)Detected Fedora/RHEL based system$(tput sgr0)"
else
  SYSTEM_TYPE="unknown"
  echo "$(tput setaf 1)Warning: Unknown system type$(tput sgr0)"
fi

# Install zsh based on system type
echo "$(tput setaf 3)Installing zsh and related packages...$(tput sgr0)"

if [ "$SYSTEM_TYPE" = "atomic" ]; then
  # Check if packages need to be installed
  PACKAGES_NEEDED=()
  
  for pkg in zsh lsd fzf tldr atuin; do
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
  else
    echo "All packages already installed"
  fi
  
elif [ "$SYSTEM_TYPE" = "debian" ]; then
  # Install zsh
  if ! command -v zsh &> /dev/null; then
    apt update
    apt install -y zsh
    echo "zsh installed"
  else
    echo "zsh already installed"
  fi
  
  # Install lsd
  if ! command -v lsd &> /dev/null; then
    echo "$(tput setaf 3)Installing lsd (LSDeluxe)...$(tput sgr0)"
    LSD_VERSION=$(curl -s https://api.github.com/repos/lsd-rs/lsd/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    wget -q "https://github.com/lsd-rs/lsd/releases/download/v${LSD_VERSION}/lsd_${LSD_VERSION}_amd64.deb" -O /tmp/lsd.deb
    dpkg -i /tmp/lsd.deb
    rm /tmp/lsd.deb
    echo "lsd installed successfully"
  else
    echo "lsd already installed"
  fi
  
  # Install fzf
  if ! command -v fzf &> /dev/null; then
    echo "$(tput setaf 3)Installing fzf...$(tput sgr0)"
    apt install -y fzf
    echo "fzf installed successfully"
  else
    echo "fzf already installed"
  fi
  
  # Install tldr
  if ! command -v tldr &> /dev/null; then
    echo "$(tput setaf 3)Installing tldr...$(tput sgr0)"
    apt install -y tldr
    echo "tldr installed successfully"
  else
    echo "tldr already installed"
  fi
  
  # Install atuin
  if ! command -v atuin &> /dev/null; then
    echo "$(tput setaf 3)Installing atuin...$(tput sgr0)"
    su - $ACTUAL_USER -c 'bash <(curl --proto "=https" --tlsv1.2 -sSf https://setup.atuin.sh)'
    echo "atuin installed successfully"
  else
    echo "atuin already installed"
  fi
  
elif [ "$SYSTEM_TYPE" = "fedora" ]; then
  # Install zsh
  if ! command -v zsh &> /dev/null; then
    dnf install -y zsh
    echo "zsh installed"
  else
    echo "zsh already installed"
  fi
  
  # Install lsd
  if ! command -v lsd &> /dev/null; then
    echo "$(tput setaf 3)Installing lsd (LSDeluxe)...$(tput sgr0)"
    dnf install -y lsd
    echo "lsd installed successfully"
  else
    echo "lsd already installed"
  fi
  
  # Install fzf
  if ! command -v fzf &> /dev/null; then
    echo "$(tput setaf 3)Installing fzf...$(tput sgr0)"
    dnf install -y fzf
    echo "fzf installed successfully"
  else
    echo "fzf already installed"
  fi
  
  # Install tldr
  if ! command -v tldr &> /dev/null; then
    echo "$(tput setaf 3)Installing tldr...$(tput sgr0)"
    dnf install -y tldr
    echo "tldr installed successfully"
  else
    echo "tldr already installed"
  fi
  
  # Install atuin
  if ! command -v atuin &> /dev/null; then
    echo "$(tput setaf 3)Installing atuin...$(tput sgr0)"
    su - $ACTUAL_USER -c 'bash <(curl --proto "=https" --tlsv1.2 -sSf https://setup.atuin.sh)'
    echo "atuin installed successfully"
  else
    echo "atuin already installed"
  fi
fi

# Install Oh My Zsh if not present
if [ ! -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  echo "$(tput setaf 3)Installing Oh My Zsh...$(tput sgr0)"
  su - $ACTUAL_USER -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
  echo "Oh My Zsh installed"
else
  echo "Oh My Zsh already installed"
fi

# Install zsh plugins if Oh My Zsh is present
if [ -d "$ACTUAL_HOME/.oh-my-zsh" ]; then
  echo "$(tput setaf 3)Checking zsh plugins...$(tput sgr0)"
  
  # Install zsh-autosuggestions
  if [ ! -d "$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    echo "zsh-autosuggestions installed"
  else
    echo "zsh-autosuggestions already present"
  fi
  
  # Install zsh-syntax-highlighting
  if [ ! -d "$ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    echo "zsh-syntax-highlighting installed"
  else
    echo "zsh-syntax-highlighting already present"
  fi
  
  # Initialize Atuin in .zshrc if installed
  if command -v atuin &> /dev/null && [ -f "$ACTUAL_HOME/.zshrc" ]; then
    if ! grep -q "atuin init zsh" "$ACTUAL_HOME/.zshrc" 2>/dev/null; then
      echo "Initializing Atuin in .zshrc..."
      echo '' >> "$ACTUAL_HOME/.zshrc"
      echo '# Atuin - magical shell history' >> "$ACTUAL_HOME/.zshrc"
      echo 'eval "$(atuin init zsh)"' >> "$ACTUAL_HOME/.zshrc"
      chown $ACTUAL_USER:$ACTUAL_USER "$ACTUAL_HOME/.zshrc"
      echo "Atuin initialized in .zshrc"
    else
      echo "Atuin already initialized in .zshrc"
    fi
  fi
fi

# Set zsh as default shell if not already set
CURRENT_SHELL=$(getent passwd $ACTUAL_USER | cut -d: -f7)
if [ "$CURRENT_SHELL" != "/usr/bin/zsh" ] && [ "$CURRENT_SHELL" != "/bin/zsh" ]; then
  echo "$(tput setaf 3)Changing default shell to zsh for $ACTUAL_USER...$(tput sgr0)"
  chsh -s $(which zsh) $ACTUAL_USER
  if [ $? -eq 0 ]; then
    echo "Default shell changed to zsh for $ACTUAL_USER"
  else
    echo "Warning: Failed to change default shell to zsh"
  fi
else
  echo "Default shell is already zsh for $ACTUAL_USER"
fi

echo ""
echo "$(tput setaf 2)========================================"$(tput sgr0)"
echo "$(tput setaf 2)Zsh setup completed successfully!$(tput sgr0)"
echo "$(tput setaf 2)========================================$(tput sgr0)"
echo ""
echo "Installed components:"
echo "  ✓ Zsh shell"
echo "  ✓ Oh My Zsh framework"
echo "  ✓ zsh-autosuggestions plugin"
echo "  ✓ zsh-syntax-highlighting plugin"
if command -v lsd &> /dev/null; then
  echo "  ✓ LSD (LSDeluxe) - modern ls replacement"
fi
if command -v fzf &> /dev/null; then
  echo "  ✓ fzf - command-line fuzzy finder"
fi
if command -v tldr &> /dev/null; then
  echo "  ✓ tldr - simplified man pages"
fi
if command -v atuin &> /dev/null; then
  echo "  ✓ Atuin - magical shell history"
fi
echo ""
echo "$(tput setaf 3)IMPORTANT:$(tput sgr0)"
echo "- Log out and log back in for the shell change to take effect"
echo "- Or start a new zsh session with: zsh"
echo ""
