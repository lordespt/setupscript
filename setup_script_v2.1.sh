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

# Function to discover and mount drives with nofail option
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
            
            # Check if the entry already exists in /etc/fstab
            if ! grep -qs "UUID=$UUID" /etc/fstab; then
                echo "Adding new entry to /etc/fstab: UUID=$UUID $MOUNTPOINT $FSTYPE defaults,nofail 0 2"
                echo "UUID=$UUID $MOUNTPOINT $FSTYPE defaults,nofail 0 2" >> /etc/fstab
            else
                echo "Entry for UUID=$UUID already exists in /etc/fstab. Skipping."
            fi
        fi
    done

    # Mount all drives listed in /etc/fstab
    mount -a
}

# Install and Switch to Low-Latency Kernel
echo "Installing and switching to the low-latency kernel..."

check_install linux-lowlatency

# Set low-latency kernel as the default
sudo sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux lowlatency"/g' /etc/default/grub
sudo update-grub

echo "Low-latency kernel installed and set as default."

# Optimize CPU Performance
echo "Optimizing CPU performance by setting the governor to 'performance'..."

check_install cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils

echo "CPU performance optimized."

# Disable Unnecessary Power Management
echo "Disabling unnecessary power management features..."

# Update GRUB for Power Management Settings
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_pstate=disable"/g' /etc/default/grub
sudo update-grub

echo "Power management settings updated. A reboot is required to apply these changes."

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

# Install Remmina and XRDP
check_install remmina
check_install remmina-plugin-rdp
check_install xrdp

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

check_install nfs-common
check_install cifs-utils
check_install smbclient

configure_nas_drives() {
    showmount -e | grep 'Export list' > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "NFS shares detected."
        showmount -e | tail -n +2 | while read -r line; do
            NAS_PATH=$(echo $line | awk '{print $1}')
            MOUNTPOINT="/mnt/nfs/$(basename $NAS_PATH)"
            mkdir -p "$MOUNTPOINT"
            if ! grep -qs "$NAS_PATH" /etc/fstab; then
                echo "$NAS_PATH $MOUNTPOINT nfs defaults,nofail 0 0" >> /etc/fstab
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
                echo "$NAS_PATH $MOUNTPOINT cifs username=$NAS_USERNAME,password=$NAS_PASSWORD,iocharset=utf8,sec=ntlm,nofail 0 0" >> /etc/fstab
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
        echo "UUID=\$UUID \$MOUNTPOINT \$FSTYPE defaults,nofail 0 2" >> /etc/fstab
    fi
done

mount -a
EOF

chmod +x /usr/local/bin/handle-drive-swap.sh

udevadm control --reload-rules
udevadm trigger

echo "Drive swap handling configured."

# Customize Login Experience with MOTD and Issue Messages

# Disable Default MOTD Components
echo "Disabling default Ubuntu MOTD components..."
sudo chmod -x /etc/update-motd.d/*

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
echo "***************************************************"
echo "$logo"
echo "***************************************************"
echo "Enjoy your high-fidelity audio playback experience."
echo "***************************************************"
EOF

# Make the custom MOTD script executable
sudo chmod +x /etc/update-motd.d/99-custom-motd

# Install ALSA and PulseAudio Tweaks
echo "Installing ALSA and PulseAudio tweaks for optimal audio playback quality..."

check_install alsa-utils
check_install pulseaudio

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
