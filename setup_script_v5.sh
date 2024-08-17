#!/bin/bash

# Function to check if a package is installed, and install if it's missing
check_install() {
    PACKAGE=$1
    if ! dpkg -l | grep -q "$PACKAGE"; then
        echo "Installing $PACKAGE..."
        # Ensure dpkg is in a consistent state
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
    "udisks2"  # Handles drive automounting and management
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
)

echo "Installing essential packages..."
for pkg in "${essential_packages[@]}"; do
    check_install $pkg
done

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

# Auto-mount for drives using udisks2
echo "Configuring auto-mount for drives..."
sudo tee /etc/udev/rules.d/99-local.rules > /dev/null <<EOF
KERNEL=="sd[a-z][0-9]", ACTION=="add", ENV{ID_FS_TYPE}=="ntfs|vfat|ext4", RUN+="/usr/bin/udisksctl mount -b %N"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

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
 / _ \  / _ \ | ___ \/  __ \  _  \
/ /_\ \/ /_\ \| |_/ /| /  \/ | | |
|  _  ||  _  ||  __/ | |   | | | |
| | | || | | || |    | \__/\ |/ / 
\_| |_/\_| |_/\_|     \____/___/  
                                  
                                  


                                 
Advanced Audio PC Distribution
Maintained by lordepst
"

# Disable Default MOTD Components
echo "Disabling default Ubuntu MOTD components..."
sudo chmod -x /etc/update-motd.d/*

# Create Custom MOTD Script
echo "Creating custom MOTD script..."
sudo tee /etc/update-motd.d/99-custom-motd > /dev/null <<EOF
#!/bin/bash

echo "***************************************************"
echo "Welcome to Your Advanced Audio Playback PC"
echo "Hostname: \$(hostname)"
echo "Local IP Address: \$(hostname -I | awk '{print \$1}')"
echo "Public IP Address: \$(curl -s https://api.ipify.org)"
echo "System Uptime: \$(uptime -p)"
echo "***************************************************"
echo "Roon Server Status: \$(systemctl is-active roonserver)"
echo "CPU Governor: \$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)"
echo "Low Latency Kernel: \$(uname -r | grep -q lowlatency && echo Yes || echo No)"
echo "***************************************************"
echo "$logo"
echo "***************************************************"
echo "Advanced Audio Playback PC - Welcome!"
echo "Enjoy your high-fidelity audio playback experience with Roon."
echo "***************************************************"
EOF

# Make the custom MOTD script executable
sudo chmod +x /etc/update-motd.d/99-custom-motd

# Final Message
echo "Setup complete! Your Advanced Audio PC login experience is now personalized."
echo "A reboot is required to apply power management settings."
