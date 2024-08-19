#!/bin/bash

sudo tee /etc/update-motd.d/99-custom-motd > /dev/null <<'EOF'
#!/bin/bash

# Clear previous MOTD content
> /etc/motd

# System Information
HOSTNAME="$(hostname)"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
PUBLIC_IP="$(curl -s https://api.ipify.org)"
UPTIME="$(uptime -p)"
CPU_TEMP="$([ -x /usr/bin/sensors ] && /usr/bin/sensors | grep 'Package id 0:' | awk '{print $4}')"
LOAD_AVG="$(uptime | awk -F'load average:' '{print $2}' | xargs)"
CPU_USAGE="$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')"
PROCS="$(ps -e --no-headers | wc -l)"

# Display MOTD
{
echo "***************************************************"
echo "Welcome to Your Advanced Audio Playback PC"
echo "Hostname: $HOSTNAME"
echo "Local IP Address: $LOCAL_IP"
echo "Public IP Address: $PUBLIC_IP"
echo "System Uptime: $UPTIME"
echo "CPU Temperature: $CPU_TEMP"
echo "System Load (1, 5, 15 min): $LOAD_AVG"
echo "CPU Usage: $CPU_USAGE"
echo "Running Processes: $PROCS"
echo "***************************************************"
echo "Roon Server Status: $(systemctl is-active roonserver)"
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)"
echo "Low Latency Kernel: $(uname -r | grep -q lowlatency && echo Yes || echo No)"
echo "***************************************************"

cat << "LOGO"
  ___    ___  ______  ___________ 
 / _ \  / _ \ | ___ \/  __ \  _  \
/ /_\ \/ /_\ \| |_/ /| /  \/ | | |
|  _  ||  _  ||  __/ | |   | | | |
| | | || | | || |    | \__/\ |/ / 
\_| |_/\_| |_/\_|     \____/___/  
                                  
                                  
Advanced Audio PC Distribution
Maintained by lordepst
LOGO

echo "***************************************************"
echo "Advanced Audio Playback PC - Welcome!"
echo "Enjoy your high-fidelity audio playback experience with Roon."
echo "***************************************************"
} > /etc/motd
EOF

sudo chmod +x /etc/update-motd.d/99-custom-motd
