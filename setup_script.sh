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

# Disable Automatic Updates
echo "Disabling automatic updates..."

# Stop and disable the unattended-upgrades service
systemctl stop unattended-upgrades
systemctl disable unattended-upgrades

# Remove the unattended-upgrades package
apt-get remove -y unattended-upgrades

# Mask the apt-daily services to prevent them from starting
systemctl mask apt-daily.service
systemctl mask apt-daily-upgrade.service

# Disable the update-notifier
echo "APT::Periodic::Update-Package-Lists \"0\";" | tee /etc/apt/apt.conf.d/10periodic
echo "APT::Periodic::Download-Upgradeable-Packages \"0\";" | tee -a /etc/apt/apt.conf.d/10periodic
echo "APT::Periodic::AutocleanInterval \"0\";" | tee -a /etc/apt/apt.conf.d/10periodic

# Prevent update prompts by removing update-notifier
apt-get purge -y update-notifier

echo "Updates disabled."

# Configure Automatic HDD/SSD Mount on Startup
echo "Configuring automatic HDD/SSD mount on startup..."

discover_drives() {
    lsblk -o UUID,NAME,FSTYPE,SIZE,MOUNTPOINT | grep -v "loop" | grep -v "SWAP" | grep -v "\[SWAP\]" | while read -r line; do
      UUID=$(echo $line | awk '{print $1}')
      NAME=$(echo $line | awk '{print $2}')
      FSTYPE=$(echo $line | awk '{print $3}')

      if [ ! -z "$UUID" ] && [ "$FSTYPE" != "" ]; then
        MOUNTPOINT="/mnt/$NAME"
        mkdir -p "$MOUNTPOINT"
        if ! grep -qs "$UUID" /etc/fstab; then
            echo "UUID=$UUID $MOUNTPOINT $FSTYPE defaults 0 2" >> /etc/fstab
        fi
      fi
    done

    # Mount all drives listed in /etc/fstab
    mount -a
}

discover_drives

echo "Automatic HDD/SSD mount configured."

# Enable Auto-login for User 'aserver'
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

# Install Remmina and Setup Permanent Connection Info
echo "Installing Remmina and setting up permanent connection info..."

# Install Remmina
check_install remmina
check_install remmina-plugin-rdp

# Create a Remmina connection profile
REMOTEDIR="/home/$USERNAME/.local/share/remmina"
mkdir -p "$REMOTEDIR"
cat << EOF > "$REMOTEDIR/YourRemoteServerName.remmina"
[remmina]
group=
name=YourRemoteServerName
protocol=RDP
server=your.dynamic.dns.or.hostname:3389
username=your_remote_username
password=your_remote_password
domain=
resolution_mode=0
color_depth=8
glyph-cache=true
precommand=
postcommand=
disableclipboard=true
disableserverbackground=true
disablemenuanimations=true
disabletheming=true
disablefullwindowdrag=true
EOF

echo "Remmina installed and connection info set up."

# Detect and Configure NAS Drives
echo "Detecting and configuring NAS drives..."

# Install necessary packages for NFS and SMB/CIFS
check_install nfs-common
check_install cifs-utils
check_install smbclient

# Function to handle NAS drive configuration
configure_nas_drives() {
    # Check for available NFS shares and add to /etc/fstab
    showmount -e | grep 'Export list' > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "NFS shares detected."
        showmount -e | tail -n +2 | while read -r line; do
            NAS_PATH=$(echo $line | awk '{print $1}')
            MOUNTPOINT="/mnt/nfs/$(basename $NAS_PATH)"
            mkdir -p "$MOUNTPOINT"
            if ! grep -qs "$NAS_PATH" /etc/fstab; then
                echo "$NAS_PATH $MOUNTPOINT nfs defaults 0 0" >> /etc/fstab
            fi
        done
    else
        echo "No NFS shares detected."
    fi

    # Check for available SMB/CIFS shares and add to /etc/fstab
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
                echo "$NAS_PATH $MOUNTPOINT cifs username=$NAS_USERNAME,password=$NAS_PASSWORD,iocharset=utf8,sec=ntlm 0 0" >> /etc/fstab
            fi
        done
    else
        echo "No SMB/CIFS shares detected."
    fi

    # Mount all NAS drives listed in /etc/fstab
    mount -a
}

configure_nas_drives

echo "NAS drive configuration completed."

# Create a systemd service for automatic discovery
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

# Enable and start the service
systemctl daemon-reload
systemctl enable discover-drives.service
systemctl start discover-drives.service

echo "Drive discovery service created and started."

# Set up udev rule to handle drive swaps
echo "Setting up udev rule for handling drive swaps..."

cat << EOF > /etc/udev/rules.d/99-driveswap.rules
KERNEL=="sd[a-z]", SUBSYSTEM=="block", ACTION=="add|remove", RUN+="/usr/local/bin/handle-drive-swap.sh"
EOF

# Create the drive swap handling script
cat << EOF > /usr/local/bin/handle-drive-swap.sh
#!/bin/bash

# Log the event (optional)
echo "\$(date): Detected drive change: \$ACTION on \$DEVNAME" >> /var/log/drive-swap.log

# Rescan for all block devices and update /etc/fstab
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
        echo "UUID=\$UUID \$MOUNTPOINT \$FSTYPE defaults 0 2" >> /etc/fstab
    fi
done

# Remount all drives
mount -a
EOF

chmod +x /usr/local/bin/handle-drive-swap.sh

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

echo "Drive swap handling configured."

echo "All tasks completed!"
