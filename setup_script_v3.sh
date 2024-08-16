#!/bin/bash

# Function to check if a package is installed
check_install() {
    PACKAGE=$1
    if dpkg -l | grep -q "$PACKAGE"; then
        echo "$PACKAGE is already installed, skipping installation."
    else
        echo "Installing $PACKAGE..."
        apt-get install -y $PACKAGE
    fi
}

# Function to clean up stale /etc/fstab entries
cleanup_fstab() {
    for uuid in $(grep '^UUID=' /etc/fstab | awk '{print $1}' | cut -d= -f2); do
        if ! lsblk -o UUID | grep -q $uuid; then
            echo "Removing stale /etc/fstab entry for UUID=$uuid"
            sudo sed -i "\|UUID=$uuid|d" /etc/fstab
        fi
    done
}

# Function to manually test drive mounting before adding to /etc/fstab
test_drive_mount() {
    UUID=$1
    MOUNTPOINT=$2
    echo "Testing mount for UUID=$UUID at $MOUNTPOINT..."
    
    # Attempt to mount the drive
    if sudo mount UUID=$UUID $MOUNTPOINT; then
        echo "Mount successful. Unmounting now..."
        sudo umount $MOUNTPOINT
    else
        echo "Mount failed for UUID=$UUID. Please check the UUID and try again."
    fi
}

# Function to discover and mount drives with optimized and compatible options
discover_drives() {
    lsblk -o UUID,NAME,FSTYPE,SIZE,MOUNTPOINT | grep -v "loop" | grep -v "SWAP" | grep -v "\[SWAP\]" | while read -r line; do
        UUID=$(echo $line | awk '{print $1}')
        NAME=$(echo $line | awk '{print $2}')
        FSTYPE=$(echo $line | awk '{print $3}')

        if [ ! -z "$UUID" ] && [ "$FSTYPE" != "" ]; then
            MOUNTPOINT="/mnt/$NAME"
            mkdir -p "$MOUNTPOINT"
            
            # Test the drive mount before adding it to fstab
            test_drive_mount "$UUID" "$MOUNTPOINT"
            
            # Set optimized mount options
            MOUNT_OPTIONS="defaults,noatime,nodiratime,nofail"
            if [ "$FSTYPE" = "ext4" ] || [ "$FSTYPE" = "btrfs" ] || [ "$FSTYPE" = "xfs" ]; then
                MOUNT_OPTIONS="$MOUNT_OPTIONS,discard"
            fi
            
            # Check if the entry already exists in /etc/fstab
            if ! grep -qs "UUID=$UUID" /etc/fstab; then
                echo "Adding new entry to /etc/fstab: UUID=$UUID $MOUNTPOINT $FSTYPE $MOUNT_OPTIONS 0 2"
                echo "UUID=$UUID $MOUNTPOINT $FSTYPE $MOUNT_OPTIONS 0 2" >> /etc/fstab
            else
                echo "Entry for UUID=$UUID already exists in /etc/fstab. Skipping."
            fi
        fi
    done

    # Mount all drives listed in /etc/fstab
    mount -a
}

# Function to detect incompatible drive formats
check_incompatible_formats() {
    incompatible_drives=()
    compatible_formats=("ext4" "ntfs" "exfat" "vfat" "btrfs" "xfs")

    lsblk -o NAME,FSTYPE | grep -v "loop" | grep -v "SWAP" | grep -v "\[SWAP\]" | while read -r line; do
        NAME=$(echo $line | awk '{print $1}')
        FSTYPE=$(echo $line | awk '{print $2}')

        if [ ! -z "$FSTYPE" ]; then
            if [[ ! " ${compatible_formats[@]} " =~ " ${FSTYPE} " ]]; then
                incompatible_drives+=("$NAME ($FSTYPE)")
            fi
        fi
    done

    if [ ${#incompatible_drives[@]} -ne 0 ]; then
        echo "Incompatible drive formats detected: ${incompatible_drives[@]}"
        echo "WARNING: The following drives have incompatible formats: ${incompatible_drives[@]}" > /etc/motd.incompatible_drives
    else
        echo "" > /etc/motd.incompatible_drives
    fi
}

# Run the incompatible format check
check_incompatible_formats

# Install packages in parallel for efficiency
packages=("cpufrequtils" "glances" "fail2ban" "remmina" "remmina-plugin-rdp" "xrdp" "nfs-common" "cifs-utils" "smbclient" "alsa-utils" "pulseaudio")
echo "Installing necessary packages in parallel..."
sudo apt-get install -y ${packages[@]} &
wait

# Install and Switch to Low-Latency Kernel
echo "Installing and switching to the low-latency kernel..."

check_install linux-lowlatency

# Set low-latency kernel as the default
sudo sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux lowlatency"/g' /etc/default/grub
sudo update-grub

echo "Low-latency kernel installed and set as default."

# Optimize CPU Performance
echo "Optimizing CPU performance by setting the governor to 'performance'..."

echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils

echo "CPU performance optimized."

# Set I/O Scheduler for SSDs to 'deadline'
echo "Setting I/O scheduler to deadline for SSDs..."
for dev in $(lsblk -d -o name,rota | awk '$2==0 {print $1}'); do
    echo deadline | sudo tee /sys/block/$dev/queue/scheduler
done

# Disable Unnecessary Power Management
echo "Disabling unnecessary power management features..."

# Update GRUB for Power Management Settings
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_pstate=disable"/g' /etc/default/grub
sudo update-grub

echo "Power management settings updated. A reboot is required to apply these changes."

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
echo "@audio   -  rtprio     99" | sudo tee -a /etc/security/limits.d/audio.conf
echo "@audio   -  nice      -19" | sudo tee -a /etc/security/limits.d/audio.conf
echo "@audio   -  memlock    unlimited" | sudo tee -a /etc/security/limits.d/audio.conf

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
echo 'echo "never" > /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.local
echo 'echo "never" > /sys/kernel/mm/transparent_hugepage/defrag' | sudo tee -a /etc/rc.local
sudo chmod +x /etc/rc.local

# SSH Hardening
echo "Hardening SSH configuration..."
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

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

# MOTD Cleanup: Disable and remove older MOTD scripts
echo "Cleaning up old MOTD components..."
sudo rm -f /etc/motd
sudo rm -f /run/motd.dynamic
sudo chmod -x /etc/update-motd.d/*

# Setup script cleanup: Remove older setup scripts in the same directory
echo "Cleaning up older setup scripts..."
find $(dirname "$0") -name "setup_audio_pc*.sh" -not -name "$(basename "$0")" -exec rm -f {} \;

# Create the custom ASCII logo
logo="
  ___    ___  ______  ___________ 
 / _ \  / _ \ | ___ \/  __ \  _  \\
/ /_\ \/ /_\ \| |_/ /| /  \/ | | |
|  _  ||  _  ||  __/ | |   | | | |
| | | || | | || |    | \__/\ |/ / 
\_| |_/\_| |_/\_|     \____/___/  
                                  
                                  
Advanced Audio PC Distribution
Maintained by lordepst
"

# Disable Automatic Updates
echo "Disabling automatic updates..."

systemctl stop unattended-upgrades
systemctl disable unattended-upgrades

apt-get remove -y unattended-upgrades

systemctl mask apt-daily.service
systemctl mask apt-daily-upgrade.service

echo "APT::Periodic::Update-Package-Lists \"0\";" | tee /etc/apt/apt.conf.d/10periodic
echo "APT::Periodic::Download-Upgradeable-Packages \"0\";" | tee -a /etc/apt/apt.conf.d/10periodic
echo "APT::Periodic::AutocleanInterval \"0\";" | tee -a /etc/apt/apt.conf.d/10periodic

apt-get purge -y update-notifier

echo "Updates disabled."

# Clean up stale fstab entries
echo "Cleaning up stale /etc/fstab entries..."
cleanup_fstab

# Configure Automatic HDD/SSD Mount on Startup
echo "Configuring automatic HDD/SSD mount on startup..."

discover_drives

echo "Automatic HDD/SSD mount configured."

# Enable Auto-login
echo "Enabling auto-login..."

USERNAME="aserver"

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat << EOF > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

systemctl enable getty@tty1.service

echo "Auto-login enabled for user $USERNAME."

# Install Remmina and XRDP, Setup Firewall for SSH and RDP
echo "Installing Remmina, XRDP, and configuring firewall..."

# Configure XRDP to allow remote RDP connections
sudo systemctl enable xrdp
sudo systemctl start xrdp

# Open firewall ports for SSH (22) and RDP (3389)
sudo ufw allow 22/tcp
sudo ufw allow 3389/tcp
sudo ufw reload

echo "SSH and RDP firewall rules configured."

# Fetch the public IP address
PUBLIC_IP=$(curl -s https://api.ipify.org)

# Setup Remmina profile for remote access using public IP
REMOTEDIR="/home/$USERNAME/.local/share/remmina"
mkdir -p "$REMOTEDIR"
cat << EOF > "$REMOTEDIR/Remote-Access.remmina"
[remmina]
group=Remote Connections
name=Remote Access to Advanced Audio PC
protocol=RDP
server=$PUBLIC_IP:3389
username=$USERNAME
password=
domain=
resolution_mode=0
color_depth=32
glyph-cache=true
precommand=
postcommand=
disableclipboard=false
disableserverbackground=false
disablemenuanimations=false
disabletheming=false
disablefullwindowdrag=false
EOF

# Fix permissions
chown -R $USERNAME:$USERNAME "$REMOTEDIR"

echo "Remmina installed and remote access configured using public IP: $PUBLIC_IP"

# Detect and Configure NAS Drives
echo "Detecting and configuring NAS drives..."

configure_nas_drives() {
    showmount -e | grep 'Export list' > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "NFS shares detected."
        showmount -e | tail -n +2 | while read -r line; do
            NAS_PATH=$(echo $line | awk '{print $1}')
            MOUNTPOINT="/mnt/nfs/$(basename $NAS_PATH)"
            mkdir -p "$MOUNTPOINT"
            if ! grep -qs "$NAS_PATH" /etc/fstab; then
                echo "$NAS_PATH $MOUNTPOINT nfs defaults,nofail,noatime,nodiratime 0 0" >> /etc/fstab
            fi
        done
    else
        echo "No NFS shares detected."
    fi

    smbclient -L localhost -N > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "SMB/CIFS shares detected."
        smbclient -L localhost -N | grep 'Disk' | while read -r line; do
            NAS_NAME=$(echo $line | awk '{print $1}')
            NAS_PATH="//$HOSTNAME/$NAS_NAME"
            MOUNTPOINT="/mnt/smb/$NAS_NAME"
            mkdir -p "$MOUNTPOINT"
            if ! grep -qs "$NAS_PATH" /etc/fstab; then
                read -p "Enter username for $NAS_PATH: " NAS_USERNAME
                read -sp "Enter password for $NAS_PATH: " NAS_PASSWORD
                echo
                echo "$NAS_PATH $MOUNTPOINT cifs username=$NAS_USERNAME,password=$NAS_PASSWORD,iocharset=utf8,sec=ntlm,nofail,noatime,nodiratime 0 0" >> /etc/fstab
            fi
        done
    else
        echo "No SMB/CIFS shares detected."
    fi

    mount -a
}

configure_nas_drives

echo "NAS drive configuration completed."

# Create a Systemd Service for Drive Discovery
echo "Creating systemd service for drive discovery..."

cat << EOF > /etc/systemd/system/discover-drives.service
[Unit]
Description=Discover and mount drives (HDD/SSD/NAS)
After=network-online.target

[Service]
ExecStart=/usr/local/bin/discover-drives.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /usr/local/bin/discover-drives.sh
#!/bin/bash
$(declare -f discover_drives)
$(declare -f configure_nas_drives)
discover_drives
configure_nas_drives
EOF

chmod +x /usr/local/bin/discover-drives.sh

systemctl daemon-reload
systemctl enable discover-drives.service
systemctl start discover-drives.service

echo "Drive discovery service created and started."

# Setup Udev Rule for Handling Drive Swaps
echo "Setting up udev rule for handling drive swaps..."

cat << EOF > /etc/udev/rules.d/99-driveswap.rules
KERNEL=="sd[a-z]", SUBSYSTEM=="block", ACTION=="add|remove", RUN+="/usr/local/bin/handle-drive-swap.sh"
EOF

cat << EOF > /usr/local/bin/handle-drive-swap.sh
#!/bin/bash

echo "\$(date): Detected drive change: \$ACTION on \$DEVNAME" >> /var/log/drive-swap.log

lsblk -o UUID,NAME,FSTYPE,SIZE,MOUNTPOINT | grep -v "loop" | grep -v "SWAP" | grep -v "\[SWAP\]" | while read -r line; do
    UUID=\$(echo \$line | awk '{print \$1}')
    NAME=\$(echo \$line | awk '{print \$2}')
    FSTYPE=\$(echo \$line | awk '{print \$3}')
    
    if [ ! -z "\$UUID" ] && [ "\$FSTYPE" != "" ]; then
        MOUNTPOINT="/mnt/\$NAME"
        mkdir -p "\$MOUNTPOINT"
        
        # Remove any old entries for this mount point
        sed -i "\|$MOUNTPOINT|d" /etc/fstab
        
        # Add new entry
        echo "UUID=\$UUID \$MOUNTPOINT \$FSTYPE defaults,nofail,noatime,nodiratime 0 2" >> /etc/fstab
    fi
done

mount -a
EOF

chmod +x /usr/local/bin/handle-drive-swap.sh

udevadm control --reload-rules
udevadm trigger

echo "Drive swap handling configured."

# Customize Login Experience with MOTD and Issue Messages

# Create Custom MOTD Script
echo "Creating custom MOTD script..."
sudo cat << EOF > /etc/update-motd.d/99-custom-motd
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
cat /etc/motd.incompatible_drives
echo "***************************************************"
echo "$logo"
echo "***************************************************"
echo "Advanced Audio Playback PC - Welcome!"
echo "Enjoy your high-fidelity audio playback experience with Roon."
echo "***************************************************"
EOF

# Make the custom MOTD script executable
sudo chmod +x /etc/update-motd.d/99-custom-motd

# Install ALSA and PulseAudio Tweaks
echo "Installing ALSA and PulseAudio tweaks for optimal audio playback quality..."

# Configure PulseAudio
sudo sed -i 's/^; resample-method = speex-float-1/resample-method = src-sinc-best-quality/' /etc/pulse/daemon.conf
sudo sed -i 's/^; default-sample-format = s16le/default-sample-format = s32le/' /etc/pulse/daemon.conf
sudo sed -i 's/^; default-sample-rate = 44100/default-sample-rate = 44100/' /etc/pulse/daemon.conf
sudo sed -i 's/^; alternate-sample-rate = 48000/alternate-sample-rate = 48000/' /etc/pulse/daemon.conf

echo "ALSA and PulseAudio configured."

# Final Message
echo "Setup complete! Your Advanced Audio PC login experience is now personalized."
echo "You can remotely access this machine using the public IP: $PUBLIC_IP"
echo "A reboot is required to apply power management settings."

# Delete the script itself
echo "Deleting the setup script..."
rm -- "$0"
