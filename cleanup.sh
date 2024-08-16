#!/bin/bash

echo "Starting cleanup of previous script configurations and services..."

# Disable and remove the old services created by the previous scripts
services=("unattended-upgrades" "apt-daily" "apt-daily-upgrade" "getty@tty1" "xrdp" "discover-drives" "fail2ban")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "Stopping and disabling service $service..."
        systemctl stop $service
        systemctl disable $service
    fi
    if [ -f /etc/systemd/system/$service.service ]; then
        echo "Removing service $service..."
        rm -f /etc/systemd/system/$service.service
    fi
done

# Remove custom scripts and configurations added by the previous scripts
files=(
    "/etc/apt/apt.conf.d/10periodic"
    "/usr/local/bin/discover-drives.sh"
    "/usr/local/bin/handle-drive-swap.sh"
    "/etc/udev/rules.d/99-driveswap.rules"
    "/etc/systemd/system/getty@tty1.service.d/override.conf"
    "/etc/rc.local"
    "/etc/update-motd.d/99-custom-motd"
    "/home/aserver/.local/share/remmina/YourRemoteServerName.remmina"
    "/home/aserver/.local/share/remmina/Remote-Access.remmina"
)
for file in "${files[@]}"; do
    if [ -f $file ]; then
        echo "Removing file $file..."
        rm -f $file
    else
        echo "File $file does not exist, skipping removal."
    fi
done

# Clean up the /etc/fstab file from any modifications made by previous scripts
echo "Cleaning up /etc/fstab..."
if [ -f /etc/fstab.bak ]; then
    cp /etc/fstab.bak /etc/fstab
    echo "/etc/fstab restored from backup."
else
    echo "No backup of /etc/fstab found. Proceeding with manual cleanup."
    for uuid in $(grep '^UUID=' /etc/fstab | awk '{print $1}' | cut -d= -f2); do
        if ! lsblk -o UUID | grep -q $uuid; then
            echo "Removing stale /etc/fstab entry for UUID=$uuid"
            sudo sed -i "\|UUID=$uuid|d" /etc/fstab
        fi
    done
fi

# Ensure the systemd daemon is reloaded to apply all changes
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Restore GRUB settings to default
echo "Restoring GRUB settings to default..."
sudo sed -i 's/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux lowlatency"/GRUB_DEFAULT=0/g' /etc/default/grub
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_pstate=disable"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/g' /etc/default/grub
sudo update-grub

# Restore original PulseAudio configuration
echo "Restoring PulseAudio configuration..."
sudo sed -i 's/resample-method = src-sinc-best-quality/; resample-method = speex-float-1/' /etc/pulse/daemon.conf
sudo sed -i 's/default-sample-format = s32le/; default-sample-format = s16le/' /etc/pulse/daemon.conf
sudo sed -i 's/default-sample-rate = 44100/; default-sample-rate = 44100/' /etc/pulse/daemon.conf
sudo sed -i 's/alternate-sample-rate = 48000/; alternate-sample-rate = 48000/' /etc/pulse/daemon.conf

# Unmask any masked services
echo "Unmasking any masked services..."
systemctl unmask apt-daily.service
systemctl unmask apt-daily-upgrade.service

# Remove any leftover directories
echo "Removing leftover directories..."
dirs=("/mnt/nfs" "/mnt/smb" "/mnt/usb_*")
for dir in "${dirs[@]}"; do
    if [ -d $dir ]; then
        echo "Removing directory $dir..."
        rm -rf $dir
    fi
done

echo "Cleanup completed. Your system should now be free of configurations from previous script versions."
