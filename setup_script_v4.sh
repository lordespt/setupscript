#!/bin/bash

# Function to check if a package is installed, and install if it's missing
check_install() {
    PACKAGE=$1
    if dpkg -l | grep -q "$PACKAGE"; then
        echo "$PACKAGE is already installed, skipping installation."
    else
        echo "Installing $PACKAGE..."
        # Ensure dpkg is in a consistent state
        sudo dpkg --configure -a
        sudo apt-get install -f
        if ! apt-get install -y $PACKAGE; then
            echo "Failed to install $PACKAGE. Please check your package manager status."
            exit 1
        fi
    fi
}

# Update package list and upgrade all packages
echo "Updating package list and upgrading installed packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install essential packages
essential_packages=(
    "software-properties-common"
    "apt-transport-https"
    "curl"
    "wget"
    "git"
    "net-tools"
    "lsb-release"
    "ca-certificates"
    "ufw"
    "htop"
    "ffmpeg"
    "libavcodec-extra"
    "libavutil-dev"
    "pulseaudio"
    "alsa-utils"
    "ssh"
    "ethtool"
    "fail2ban"
)

echo "Installing essential packages..."
for pkg in "${essential_packages[@]}"; do
    check_install $pkg
done

# Install and configure Roon Server
install_roon_server() {
    echo "Installing Roon Server..."

    # Roon Server installation script
    ROON_SERVER_SCRIPT=$(cat << 'END_SCRIPT'
#!/bin/bash

# blow up on non-zero exit code
set -e

# these are replaced by build.sh
PACKAGE_NAME=RoonServer
ARCH=x64
PACKAGE_URL=https://download.roonlabs.net/builds/RoonServer_linuxx64.tar.bz2
PACKAGE_FILE=${PACKAGE_NAME}_linux${ARCH}.tar.bz2
PACKAGE_NAME_LOWER=`echo "$PACKAGE_NAME" | tr "[A-Z]" "[a-z]"`

TMPDIR=`mktemp -d`
MACHINE_ARCH=`uname -m`
OK=0

CLEAN_EXIT=0

# for colorization
ESC_SEQ="\033["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"
COL_BLUE=$ESC_SEQ"34;01m"
COL_MAGENTA=$ESC_SEQ"35;01m"
COL_CYAN=$ESC_SEQ"36;01m"
COL_BOLD=$ESC_SEQ"1m"

function hr {
    echo -e "${COL_BOLD}--------------------------------------------------------------------------------------${COL_RESET}"
}

function clean_up { 
    rm -Rf $TMPDIR
    if [ x$CLEAN_EXIT != x1 ]; then
        echo ""
        hr
        echo ""
        echo -e "${COL_BOLD}${COL_RED}The $PACKAGE_NAME installer did not complete successfully.${COL_RESET}"
        echo ""
        echo "If you are not sure how to proceed, please check out:"
        echo ""
        echo " - Roon Labs Community            https://community.roonlabs.com/c/support"
        echo " - Roon Labs Knowledge Base       https://kb.roonlabs.com/LinuxInstall"
        echo ""
        hr
        echo ""
    fi
}
trap clean_up EXIT

function install {
    #
    # Print banner/message
    #
    echo ""
    hr
    echo ""
    echo -e "${COL_BOLD}Welcome to the $PACKAGE_NAME installer${COL_RESET}"
    echo ""
    echo "This installer sets up $PACKAGE_NAME to run on linux with the following settings:" 
    echo ""
    echo " - $PACKAGE_NAME will be installed in /opt/$PACKAGE_NAME"
    echo " - $PACKAGE_NAME's data will be stored in /var/roon/$PACKAGE_NAME"
    echo " - $PACKAGE_NAME will be configured to run as a system service"
    echo " - $PACKAGE_NAME will run as root"
    echo ""
    echo "These settings are suitable for turning a dedicated or semi-dedicated device"
    echo "into an appliance that runs $PACKAGE_NAME"
    echo ""
    echo "If you want customize how $PACKAGE_NAME is installed, see:"
    echo ""
    echo "   http://kb.roonlabs.com/LinuxInstall"
    echo ""
    hr
    echo ""


    #
    # Check for linux (in case someone runs on OS X, Cygwin, BSD, etc)
    #
    case `uname -s` in 
        Linux)
            ;;
        *)
            echo -e "${COL_RED}${COL_BLOLD}Error:${COL_RESET} This package is intended for Linux platforms. It is not compatible with your machine. Exiting."
            ;;
    esac

    #
    # Check for proper architecture
    #
    case "$MACHINE_ARCH" in
        armv7*)
            if [ x$ARCH = xarmv7hf ]; then OK=1; fi
            ;;
        aarch64*)
            if [ x$ARCH = xarmv8 ]; then OK=1; fi
            if [ x$ARCH = xarmv7hf ]; then OK=1; fi
            ;;
        x86_64*)
            if [ x$ARCH = xx64 ]; then OK=1; fi 
            ;;
        i686*)
            if [ x$ARCH = xx86 ]; then OK=1; fi 
            ;;
    esac

    #
    # Check for root privileges
    #
    if [ x$UID != x0 ]; then
        echo ""
        echo -e "${COL_RED}${COL_BLOLD}Error:${COL_RESET} This installer must be run with root privileges. Exiting."
        echo ""
        exit 2
    fi

    #
    # Check for ffmpeg/avconv
    #

    if [ x$OK != x1 ]; then
        echo ""
        echo -e "${COL_RED}${COL_BLOLD}Error:${COL_RESET} This package is intended for $ARCH platforms. It is not compatible with your machine. Exiting."
        echo ""
        exit 3
    fi

    function confirm_n {
        while true; do
            read -p "$1 [y/N] " yn
            case $yn in
                [Yy]* ) 
                    break 
                    ;;
                "") 
                    CLEAN_EXIT=1
                    echo ""
                    echo "Ok. Exiting."
                    echo ""
                    exit 4 
                    ;;
                [Nn]* ) 
                    CLEAN_EXIT=1
                    echo ""
                    echo "Ok. Exiting."
                    echo ""
                    exit 4 
                    ;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    }

    function confirm {
        while true; do
            read -p "$1 [Y/n] " yn
            case $yn in
                "") 
                    break 
                    ;;
                [Yy]* ) 
                    break 
                    ;;
                [Nn]* ) 
                    CLEAN_EXIT=1
                    echo ""
                    echo "Ok. Exiting."
                    echo ""
                    exit 4 
                    ;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    }

    #
    # Double-check with user that this is what they want
    #
    confirm "Do you want to install $PACKAGE_NAME on this machine?"

    echo ""
    echo "Downloading $PACKAGE_FILE to $TMPDIR/$PACKAGE_FILE"
    echo ""
    set +e
    which wget >/dev/null; WHICH_WGET=$?
    set -e
    if [ $WHICH_WGET = 0 ]; then
        wget --show-progress -O "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_URL"
    else
        curl -L -# -o "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_URL"
    fi
        
    echo ""
    echo -n "Unpacking ${PACKAGE_FILE}..."
    cd $TMPDIR
    tar xf "$PACKAGE_FILE"
    echo "Done"

    if [ ! -d "$TMPDIR/$PACKAGE_NAME" ]; then 
        echo "Missing directory: $TMPDIR/$PACKAGE_NAME. This indicates a broken package."
        exit 5
    fi

    if [ ! -f "$TMPDIR/$PACKAGE_NAME/check.sh" ]; then 
        echo "Missing $TMPDIR/$PACKAGE_NAME/check.sh. This indicates a broken package."
        exit 5
    fi

    $TMPDIR/$PACKAGE_NAME/check.sh

    if [ -e /opt/$PACKAGE_NAME ]; then
        hr
        echo ""
        echo -e "${COL_RED}${COL_BOLD}Warning:${COL_RESET} The /opt/$PACKAGE_NAME directory already exists."
        echo ""
        echo "This usually indicates that $PACKAGE_NAME was installed previously on this machine. The previous"
        echo "installation must be deleted before the installation can proceed."
        echo ""
        echo "Under normal circumstances, this directory does not contain any user data, so it should be safe to delete it."
        echo ""
        hr
        echo ""
        confirm "Delete /opt/$PACKAGE_NAME and re-install?"
        rm -Rf /opt/$PACKAGE_NAME
    fi

    echo ""
    echo -n "Copying Files..."
    mv "$TMPDIR/$PACKAGE_NAME" /opt
    echo "Done"

    # set up systemd 
    HAS_SYSTEMCTL=1; which systemctl >/dev/null || HAS_SYSTEMCTL=0

    if [ $HAS_SYSTEMCTL = 1 -a -d /etc/systemd/system ]; then
        SERVICE_FILE=/etc/systemd/system/${PACKAGE_NAME_LOWER}.service

        # stop in case it's running from an old install
        systemctl stop $PACKAGE_NAME_LOWER || true

        echo ""
        echo "Installing $SERVICE_FILE"

        cat > $SERVICE_FILE << END_SYSTEMD
[Unit]
Description=$PACKAGE_NAME
After=network-online.target

[Service]
Type=simple
User=root
Environment=ROON_DATAROOT=/var/roon
Environment=ROON_ID_DIR=/var/roon
ExecStart=/opt/$PACKAGE_NAME/start.sh
Restart=on-abort

[Install]
WantedBy=multi-user.target
END_SYSTEMD

        echo ""
        echo "Enabling service ${PACKAGE_NAME_LOWER}..."
        systemctl enable ${PACKAGE_NAME_LOWER}.service
        echo "Service Enabled"

        echo ""
        echo "Starting service ${PACKAGE_NAME_LOWER}..."
        systemctl start ${PACKAGE_NAME_LOWER}.service
        echo "Service Started"
    else
        echo ""

        SERVICE_FILE=/etc/init.d/${PACKAGE_NAME_LOWER}

        /etc/init.d/$PACKAGE_NAME_LOWER stop || true

        cat > $SERVICE_FILE << END_LSB_INIT
#!/bin/sh

### BEGIN INIT INFO
# Provides:          ${PACKAGE_NAME_LOWER}
# Required-Start:    \$network
# Required-Stop:     \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Runs ${PACKAGE_NAME}
### END INIT INFO

# Defaults
DAEMON_NAME="$PACKAGE_NAME"
DAEMON_EXECUTABLE="/opt/$PACKAGE_NAME/start.sh"
DAEMON_OPTIONS=""
DAEMON_HOMEDIR="/opt/$PACKAGE_NAME"
DAEMON_PIDFILE="/var/run/${PACKAGE_NAME_LOWER}.pid"
DAEMON_LOGFILE="/var/log/${PACKAGE_NAME_LOWER}.log"
INIT_SLEEPTIME="2"

export ROON_DATAROOT=/var/roon
export ROON_ID_DIR=/var/roon

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin

if test -f /lib/lsb/init-functions; then
    . /lib/lsb/init-functions
fi
if test -f /etc/init.d/functions; then
    . /etc/init.d/functions
fi

### DO NOT EDIT BELOW THIS POINT ###

is_running () {
    # Test whether pid file exists or not
    test -f \$DAEMON_PIDFILE || return 1

    # Test whether process is running or not
    read PID < "\$DAEMON_PIDFILE"
    ps -p \$PID >/dev/null 2>&1 || return 1

    # Is running
    return 0
}

root_only () {
    if [ "\$(id -u)" != "0" ]; then
        echo "Only root should run this operation"
        exit 1
    fi
}

run () {
    if is_running; then
        PID="\$(cat \$DAEMON_PIDFILE)"
        echo "Daemon is already running as PID \$PID"
        return 1
    fi

    cd \$DAEMON_HOMEDIR

    nohup \$DAEMON_EXECUTABLE \$DAEMON_OPTIONS >>\$DAEMON_LOGFILE 2>&1 &
    echo \$! > \$DAEMON_PIDFILE
    read PID < "\$DAEMON_PIDFILE"

    sleep \$INIT_SLEEPTIME
    if ! is_running; then
        echo "Daemon died immediately after starting. Please check your logs and configurations."
        return 1
    fi

    echo "Daemon is running as PID \$PID"
    return 0
}

stop () {
    if is_running; then
        read PID < "\$DAEMON_PIDFILE"
        kill \$PID
    fi
    sleep \$INIT_SLEEPTIME
    if is_running; then
        while is_running; do
            echo "waiting for daemon to die (PID \$PID)"
            sleep \$INIT_SLEEPTIME
        done
    fi
    rm -f "\$DAEMON_PIDFILE"
    return 0
}

case "\$1" in
    start)
        root_only
        log_daemon_msg "Starting \$DAEMON_NAME"
        run
        log_end_msg \$?
        ;;
    stop)
        root_only
        log_daemon_msg "Stopping \$DAEMON_NAME"
        stop
        log_end_msg \$?
        ;;
    restart)
        root_only
        \$0 stop && \$0 start
        ;;
    status)
        status_of_proc \
            -p "\$DAEMON_PIDFILE" \
            "\$DAEMON_EXECUTABLE" \
            "\$DAEMON_NAME" \
            && exit 0 \
            || exit \$?
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac
END_LSB_INIT

        echo "wrote out file"
        chmod +x ${SERVICE_FILE}

        HAS_UPDATE_RC_D=1; which update-rc.d >/dev/null || HAS_UPDATE_RC_D=0
        HAS_CHKCONFIG=1; which chkconfig >/dev/null || HAS_CHKCONFIG=0

        if [ $HAS_UPDATE_RC_D = 1 ]; then
            echo ""
            echo "Enabling service ${PACKAGE_NAME_LOWER} using update-rc.d..."
            update-rc.d ${PACKAGE_NAME_LOWER} defaults
            echo "Service Enabled"
        elif [ $HAS_CHKCONFIG = 1 ]; then
            echo ""
            echo "Enabling service ${PACKAGE_NAME_LOWER} using chkconfig..."
            chkconfig --add ${PACKAGE_NAME_LOWER}
            echo "Service Enabled"
        else
            echo "Couldn't find a way to enable the init script"
            exit 1
        fi

        echo ""
        echo "Starting service ${PACKAGE_NAME_LOWER}..."
        $SERVICE_FILE stop >/dev/null 2>&1 || true
        $SERVICE_FILE start
        echo "Service Started"

        echo "Setting up $PACKAGE_NAME to run at boot using LSB scripts"
    fi

    CLEAN_EXIT=1

    echo ""
    hr
    echo ""
    echo "All Done! $PACKAGE_NAME should be running on your machine now".
    echo ""
    hr
    echo ""
}

if [ x$1 == xuninstall ]; then
    uninstall
else 
    install
fi
END_SCRIPT
    )

    echo "$ROON_SERVER_SCRIPT" > /tmp/install_roon.sh
    chmod +x /tmp/install_roon.sh
    /tmp/install_roon.sh
}

# Install packages in parallel for efficiency
packages=("cpufrequtils" "glances" "remmina" "remmina-plugin-rdp" "xrdp" "nfs-common" "cifs-utils" "smbclient" "unattended-upgrades" "monit" "auto-cpufreq")
echo "Installing necessary packages in parallel..."
sudo apt-get install -y ${packages[@]} &
wait

# Dynamic Performance Tuning
echo "Installing and configuring auto-cpufreq for dynamic performance tuning..."
sudo auto-cpufreq --install

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

# Ensure SSH keys are set up before disabling password auth
if [ ! -f ~/.ssh/authorized_keys ]; then
    echo "Warning: No SSH keys found in ~/.ssh/authorized_keys. SSH password authentication will remain enabled."
else
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
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
sudo sed -i '/^Unattended-Upgrade::Origins-Pattern {/a \
"origin=Debian,codename=${distro_codename},label=Debian-Security";' /etc/apt/apt.conf.d/50unattended-upgrades

# Configure Monitoring with Monit
echo "Configuring Monit for Roon Server monitoring..."
sudo tee /etc/monit/monitrc <<EOF
set daemon 120
    with start delay 240

set logfile /var/log/monit.log

set idfile /var/lib/monit/id
set statefile /var/lib/monit/state

include /etc/monit/conf.d/*
include /etc/monit/conf-enabled/*

check process roonserver with pidfile /var/run/roonserver.pid
    start program = "/etc/init.d/roonserver start"
    stop program  = "/etc/init.d/roonserver stop"
    if failed port 9100 protocol http then restart
    if 5 restarts within 5 cycles then timeout
EOF

sudo systemctl restart monit

# Create the custom ASCII logo
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
                echo "$NAS_PATH $MOUNTPOINT nfs defaults,noatime,nofail 0 0" >> /etc/fstab
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
                echo "$NAS_PATH $MOUNTPOINT cifs username=$NAS_USERNAME,password=$NAS_PASSWORD,iocharset=utf8,sec=ntlm,noatime,nofail 0 0" >> /etc/fstab
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
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/discover-drives.sh
Restart=on-failure
StandardOutput=journal+console
StandardError=journal+console

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

exec >> /var/log/drive-swap.log 2>&1
echo "\$(date): Detected drive change: \$ACTION on \$DEVNAME"

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
        echo "UUID=\$UUID \$MOUNTPOINT \$FSTYPE defaults,noatime,nofail 0 2" >> /etc/fstab
    fi
done

mount -a
EOF

chmod +x /usr/local/bin/handle-drive-swap.sh

udevadm control --reload-rules
udevadm trigger

echo "Drive swap handling configured."

# Improving Hot-Plug USB Drive Handling
echo "Improving hot-plug USB drive handling..."

cat << EOF > /etc/udev/rules.d/99-usb-hotplug.rules
KERNEL=="sd[a-z]*", SUBSYSTEM=="block", ACTION=="add", RUN+="/usr/local/bin/handle-usb-mount.sh"
KERNEL=="sd[a-z]*", SUBSYSTEM=="block", ACTION=="remove", RUN+="/usr/local/bin/handle-usb-unmount.sh"
EOF

cat << EOF > /usr/local/bin/handle-usb-mount.sh
#!/bin/bash
PARTITION=\$(basename \$DEVNAME)
MOUNTPOINT="/mnt/usb_\$PARTITION"
mkdir -p \$MOUNTPOINT
mount /dev/\$PARTITION \$MOUNTPOINT
echo "\$(date): Mounted USB drive \$PARTITION at \$MOUNTPOINT" >> /var/log/usb-mount.log
EOF

cat << EOF > /usr/local/bin/handle-usb-unmount.sh
#!/bin/bash
PARTITION=\$(basename \$DEVNAME)
MOUNTPOINT="/mnt/usb_\$PARTITION"
umount \$MOUNTPOINT
rm -rf \$MOUNTPOINT
echo "\$(date): Unmounted USB drive \$PARTITION from \$MOUNTPOINT" >> /var/log/usb-mount.log
EOF

chmod +x /usr/local/bin/handle-usb-mount.sh
chmod +x /usr/local/bin/handle-usb-unmount.sh

udevadm control --reload-rules
udevadm trigger

echo "Hot-plug USB drive handling improved."

# Detect and Configure Audio Interfaces
echo "Detecting and configuring connected audio interfaces..."

if aplay -l | grep -i 'Audio'; then
    echo "Audio interface detected. Configuring as the default..."
    # Setup and prioritize detected audio interfaces
    DEFAULT_CARD=$(aplay -l | grep -i 'Audio' | head -n 1 | awk -F '\:' '{print $2}' | awk '{print $1}')
    echo "defaults.pcm.card $DEFAULT_CARD" | sudo tee -a /etc/asound.conf
    echo "defaults.ctl.card $DEFAULT_CARD" | sudo tee -a /etc/asound.conf
else
    echo "No audio interfaces detected."
fi

# Network Tuning for Specific NICs
echo "Applying network tuning based on NIC type..."

NIC=$(lspci | grep -i ethernet | awk '{print $5}')
if [[ "$NIC" == "Intel" ]]; then
    echo "Applying Intel-specific NIC optimizations..."
    sudo ethtool -G eth0 rx 4096 tx 4096
    sudo ethtool -C eth0 rx-usecs 0
fi

# Further Network Optimization
echo "Optimizing TCP/IP stack for audio streaming..."
sudo tee -a /etc/sysctl.conf <<EOF
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
EOF
sudo sysctl -p

# Kernel and System Tweaks
echo "Applying kernel and system tweaks for real-time performance..."
sudo tee -a /etc/sysctl.conf <<EOF
kernel.sched_latency_ns = 1000000
kernel.sched_min_granularity_ns = 500000
kernel.sched_wakeup_granularity_ns = 1500000
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
sudo sysctl -p

# Filesystem Configuration
echo "Configuring filesystems for Roon Database..."
# Regular Filesystem Checks
echo "Scheduling regular filesystem checks..."
sudo tune2fs -c 30 /dev/sdX1  # Replace with the correct partition

# Audio Playback Optimization
echo "Optimizing audio buffer settings..."
sudo tee -a /etc/pulse/daemon.conf <<EOF
default-fragments = 8
default-fragment-size-msec = 5
EOF
sudo systemctl restart pulseaudio

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
