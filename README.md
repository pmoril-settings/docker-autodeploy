# docker-autodeploy

Automated setup scripts for fresh system installations and zsh configuration.

## Scripts

### 🚀 fresh-install.sh

Complete system setup script that installs Docker, configures disks, restores backups, and sets up the development environment.

**Usage:**
```bash
# Download and execute from GitHub (recommended for fresh installs)
sh -c "$(wget -O- https://raw.githubusercontent.com/pmoril-settings/docker-autodeploy/master/fresh-install.sh)"

# Or using curl
sh -c "$(curl -fsSL https://raw.githubusercontent.com/pmoril-settings/docker-autodeploy/master/fresh-install.sh)"

# Or if you have the script locally
sudo bash fresh-install.sh
```

---

### 🎨 setup-zsh.sh

Standalone script to configure zsh with Oh My Zsh, plugins, LSD, and Atuin. Can be executed on any system independently.

**What it installs:**
- ✅ Zsh shell
- ✅ Oh My Zsh framework
- ✅ zsh-autosuggestions plugin
- ✅ zsh-syntax-highlighting plugin
- ✅ LSD (LSDeluxe) - modern `ls` replacement
- ✅ fzf - command-line fuzzy finder
- ✅ tldr - simplified man pages
- ✅ Atuin - enhanced shell history with fuzzy search

**Usage:**
```bash
# Download and execute from GitHub
sudo bash -c "$(wget -O- https://raw.githubusercontent.com/pmoril-settings/docker-autodeploy/master/setup-zsh.sh)"

# Or using curl
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/pmoril-settings/docker-autodeploy/master/setup-zsh.sh)"

# Or if you have the script locally
sudo bash setup-zsh.sh
```

**Supported systems:**
- Bazzite / Fedora Atomic
- Debian / Ubuntu
- Fedora / RHEL

**Note:** The script is idempotent - safe to run multiple times.
