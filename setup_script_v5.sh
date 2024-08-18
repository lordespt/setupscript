#!/bin/bash

# Function to check if a package is installed, and install if it's missing
check_install() {
    PACKAGE=$1
    if ! dpkg -l | grep -q "$PACKAGE"; then
        echo "Installing $PACKAGE..."
        sudo dpkg --configure -a
        sudo apt-get install -f
        if ! apt-get install -y $PACKAGE; then
            echo "Failed to install $PACKAGE. Please check your package manager status."
            exit 1
        fi
    else
        echo "$PACKAGE is already installed, skipping installation."
    fi
}

# Update package list and upgrade all packages
echo "Updating package list and upgrading installed packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install essential packages
essential_packages=(
    "build-essential"
    "software-properties-common"
    "curl"
    "wget"
    "lsb-release"
    "apt-transport-https"
    "ca-certificates"
    "ufw"
    "htop"
    "git"
    "net-tools"
    "nano"
    "python3"
    "sudo"
    "gzip"
    "cpufrequtils"
    "ethtool"
    "openssh-server"
    "udisks2"
    "nfs-common"
    "cifs-utils"
    "smbclient"
    "xrdp"
    "remmina"
    "remmina-plugin-rdp"
    "alsa-utils"
    "pulseaudio"
    "ffmpeg"
    "libavcodec-extra"
    "libavutil-dev"
    "fail2ban"
    "monit"
    "unattended-upgrades"
    "btrfs-progs"
    "zfsutils-linux"
    "rpcbind"
    "ntfs-3g"
    "lm-sensors"
    "sysstat"
    "git"  # Required for cloning the usbmount repository
)

echo "Installing essential packages..."
for pkg in "${essential_packages[@]}"; do
    check_install $pkg
done

# Setup CPU Temperature Monitoring
echo "Setting up CPU temperature monitoring..."
sudo sensors-detect --auto
sudo systemctl restart lm-sensors

# Install auto-cpufreq using snap
echo "Installing auto-cpufreq using snap..."
sudo snap install auto-cpufreq

# Ensure rpcbind service is running
sudo systemctl enable rpcbind --now

# Install and configure Roon Server
install_roon_server() {
    echo "Installing Roon Server..."
    wget http://download.roonlabs.com/builds/roonserver-installer-linuxx64.sh
    chmod +x roonserver-installer-linuxx64.sh
    sudo ./roonserver-installer-linuxx64.sh
}

install_roon_server

# Dynamic Performance Tuning
echo "Installing and configuring auto-cpufreq for dynamic performance tuning..."
sudo auto-cpufreq --install

# Install and Switch to Low-Latency Kernel
echo "Installing and switching to the low-latency kernel..."
check_install linux-lowlatency

# Set low-latency kernel as the default
sudo sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux lowlatency"/g' /etc/default/grub
sudo update-grub

# Optimize CPU Performance
echo "Optimizing CPU performance by setting the governor to 'performance'..."
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils

# Set I/O Scheduler for SSDs to 'deadline'
echo "Setting I/O scheduler to deadline for SSDs..."
for dev in $(lsblk -d -o name,rota | awk '$2==0 {print $1}'); do
    echo deadline | sudo tee /sys/block/$dev/queue/scheduler
done

# Disable Unnecessary Power Management
echo "Disabling unnecessary power management features..."
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_pstate=disable"/g' /etc/default/grub
sudo update-grub

# Reduce Swappiness
echo "Reducing swappiness to 10..."
sudo sysctl vm.swappiness=10
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf

# Disable Swap
echo "Disabling swap to reduce latency..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Enable Real-Time Audio Scheduling
echo "Enabling real-time audio scheduling..."
sudo groupadd -r audio
sudo usermod -aG audio $USERNAME
cat <<EOF | sudo tee /etc/security/limits.d/audio.conf
@audio   -  rtprio     99
@audio   -  nice      -19
@audio   -  memlock    unlimited
EOF

# Increase File Descriptors Limit
echo "Increasing file descriptors limit..."
echo "fs.file-max = 2097152" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo "root soft nofile 2097152" | sudo tee -a /etc/security/limits.conf
echo "root hard nofile 2097152" | sudo tee -a /etc/security/limits.conf

# Tune Network Interface for Low-Latency Audio Streaming
echo "Tuning network interface for low-latency audio streaming..."
sudo ethtool -G eth0 rx 4096 tx 4096
sudo ethtool -C eth0 rx-usecs 0

# Disable Transparent Huge Pages
echo "Disabling Transparent Huge Pages (THP)..."
echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
cat <<EOF | sudo tee -a /etc/rc.local
echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
echo "never" > /sys/kernel/mm/transparent_hugepage/defrag
EOF
sudo chmod +x /etc/rc.local

# SSH Hardening
echo "Hardening SSH configuration..."
if [ -f ~/.ssh/authorized_keys ]; then
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
else
    echo "Warning: No SSH keys found in ~/.ssh/authorized_keys. SSH password authentication will remain enabled."
fi

# Configure Fail2Ban for SSH protection
echo "Configuring Fail2Ban for SSH protection..."
sudo tee /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(syslog_backend)s
maxretry = 5
EOF
sudo systemctl restart fail2ban

# Enable Unattended Upgrades for Security Patches
echo "Enabling unattended upgrades for security patches..."
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Install and Configure USB Automount using usbmount
echo "Cloning and installing usbmount from GitHub..."
git clone https://github.com/rbrito/usbmount.git
cd usbmount
sudo make install

# Ensure the usbmount service is running
sudo systemctl enable usbmount
sudo systemctl start usbmount

# Auto-login setup
echo "Enabling auto-login..."
USERNAME="aserver"  # Replace with the actual username
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF
sudo systemctl enable getty@tty1.service

# Custom MOTD setup
logo="
  ___    ___  ______  ___________ 
 / _ \  / _ \ | ___ \/  __ \  _  \\
/ /_\ \/ /_\ \| |_/ /| /  \/ | | |
|  _  ||  _  ||  __/ | |   | | | |
| | | || | | || |    | \__/\ |/ / 
\_| |_/\_| |_/\_|     \____/___/  
                                  
                                  
"

# Disable Default MOTD Components
echo "Disabling default Ubuntu MOTD components..."
sudo chmod -x /etc/update-motd.d/*

# Create Custom MOTD Script with CPU Temp, System Load, and Colors
echo "Creating custom MOTD script..."
sudo tee /etc/update-motd.d/99-custom-motd > /dev/null <<EOF
#!/bin/bash

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
BOLD="\e[1m"
RESET="\e[0m"

# System Information
HOSTNAME="\$(hostname)"
LOCAL_IP="\$(hostname -I | awk '{print \$1}')"
PUBLIC_IP="\$(curl -s https://api.ipify.org)"
UPTIME="\$(uptime -p)"
CPU_TEMP="\$(sensors | grep 'Package id 0:' | awk '{print \$4}')"
LOAD_AVG="\$(uptime | awk -F'load average:' '{print \$2}' | xargs)"

# Display MOTD
echo -e "\${BLUE}***************************************************\${RESET}"
echo -e "\${GREEN}Welcome to Your Advanced Audio Playback PC\${RESET}"
echo -e "\${BOLD}Hostname:\${RESET} \${YELLOW}\$HOSTNAME\${RESET}"
echo -e "\${BOLD}Local IP Address:\${RESET} \${YELLOW}\$LOCAL_IP\${RESET}"
echo -e "\${BOLD}Public IP Address:\${RESET} \${YELLOW}\$PUBLIC_IP\${RESET}"
echo -e "\${BOLD}System Uptime:\${RESET} \${YELLOW}\$UPTIME\${RESET}"
echo -e "\${BOLD}CPU Temperature:\${RESET} \${YELLOW}\$CPU_TEMP\${RESET}"
echo -e "\${BOLD}System Load:\${RESET} \${YELLOW}\$LOAD_AVG\${RESET}"
echo -e "\${BLUE}***************************************************\${RESET}"
echo -e "\${BOLD}Roon Server Status:\${RESET} \${YELLOW}\$(systemctl is-active roonserver)\${RESET}"
echo -e "\${BOLD}CPU Governor:\${RESET} \${YELLOW}\$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)\${RESET}"
echo -e "\${BOLD}Low Latency Kernel:\${RESET} \${YELLOW}\$(uname -r | grep -q lowlatency && echo Yes || echo No)\${RESET}"
echo -e "\${BLUE}***************************************************\${RESET}"
echo -e "\$logo"
echo -e "\${BLUE}***************************************************\${RESET}"
echo -e "\${GREEN}Advanced Audio Playback PC - Welcome!\${RESET}"
echo -e "Enjoy your high-fidelity audio playback experience with Roon."
echo -e "\${BLUE}***************************************************\${RESET}"
EOF

# Make the custom MOTD script executable
sudo chmod +x /etc/update-motd.d/99-custom-motd

# Additional Performance Tuning
echo "Applying additional performance tuning..."

# Reduce CPU power states for consistent performance
echo "Disabling deep C-states to reduce latency..."
sudo sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& intel_idle.max_cstate=1/' /etc/default/grub
sudo update-grub

# Increase TCP buffer sizes
echo "Increasing TCP buffer sizes for improved network performance..."
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sudo sysctl -p

# Disable IPv6 if not needed
echo "Disabling IPv6 to reduce network stack complexity..."
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo sysctl -p

# Optimize file system performance
echo "Optimizing filesystem performance..."
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
sudo sysctl -p

# Final Message
echo "Setup complete! Your Advanced Audio PC login experience is now personalized."
echo "A reboot is required to apply power management settings."
