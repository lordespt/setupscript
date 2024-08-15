#!/bin/bash

# Function to check if a package is installed
check_remove() {
    PACKAGE=$1
    if dpkg -l | grep -q "$PACKAGE"; then
        echo "Removing $PACKAGE..."
        apt-get remove -y $PACKAGE
    else
        echo "$PACKAGE is not installed, skipping removal."
    fi
}

# Restore Automatic Updates
echo "Restoring automatic updates..."

# Reinstall the unattended-upgrades package
apt-get install -y unattended-upgrades

# Unmask and enable the apt-daily services
systemctl unmask apt-daily.service
systemctl unmask apt-daily-upgrade.service
systemctl enable apt-daily.service
systemctl enable apt-daily-upgrade.service

# Re-enable the update-notifier
echo "Re-enabling update-notifier..."
apt-get install -y update-notifier
rm -f /etc/apt/apt.conf.d/10periodic

# Cleanup `/etc/fstab` entries added by the original script
echo "Cleaning up /etc/fstab..."

# Remove auto-added entries by matching the mount points under /mnt
sed -i '/\/mnt\//d' /etc/fstab

# Disable and Remove the Drive Discovery Service
echo "Disabling and removing the drive discovery service..."

systemctl stop discover-drives.service
systemctl disable discover-drives.service
rm -f /etc/systemd/system/discover-drives.service
rm -f /usr/local/bin/discover-drives.sh

systemctl daemon-reload

# Remove the udev rule and associated script
echo "Removing udev rule and drive swap handling script..."

rm -f /etc/udev/rules.d/99-driveswap.rules
rm -f /usr/local/bin/handle-drive-swap.sh

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Remove Remmina if installed by the original script
echo "Removing Remmina..."

check_remove remmina
check_remove remmina-plugin-rdp

# Restore original getty service configuration (disable auto-login)
echo "Restoring original getty service configuration..."

rm -f /etc/systemd/system/getty@tty1.service.d/override.conf
systemctl daemon-reload

echo "All changes reversed!"
