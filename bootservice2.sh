#!/bin/bash

# Step 1: Clear any previous versions of the script and service
OLD_SCRIPT_PATH="/usr/local/bin/start_audio_service.sh"
OLD_SERVICE_FILE="/etc/systemd/system/start_audio_service.service"
NEW_SERVICE_FILE="/etc/systemd/system/start_audio_service_tty.service"

# Remove old script and service if they exist
if [ -f "$OLD_SCRIPT_PATH" ]; then
  sudo rm -f "$OLD_SCRIPT_PATH"
fi

if [ -f "$OLD_SERVICE_FILE" ]; then
  sudo systemctl disable start_audio_service.service
  sudo rm -f "$OLD_SERVICE_FILE"
fi

if [ -f "$NEW_SERVICE_FILE" ]; then
  sudo systemctl disable start_audio_service_tty.service
  sudo rm -f "$NEW_SERVICE_FILE"
fi

# Step 2: Create the new script with TTY interaction
NEW_SCRIPT_PATH="/usr/local/bin/start_audio_service.sh"

cat << 'EOF' | sudo tee $NEW_SCRIPT_PATH > /dev/null
#!/bin/bash

# Wait for 15 seconds to allow other boot messages (including MOTD) to be displayed
sleep 15

# Redirect the prompt to the first virtual terminal (tty1)
exec </dev/tty1 >/dev/tty1 2>/dev/tty1

# Ask which service to start
read -t 60 -p "Which service would you like to start? (audirvana/roon): " SERVICE

if [ -z "$SERVICE" ]; then
  SERVICE="roon"
fi

case $SERVICE in
  audirvana)
    echo "Starting Audirvana Studio..."
    sudo systemctl start audirvanaStudio.service
    ;;
  roon)
    echo "Starting Roon Server..."
    sudo systemctl start roonserver.service
    ;;
  *)
    echo "Invalid selection. Defaulting to Roon Server..."
    sudo systemctl start roonserver.service
    ;;
esac
EOF

sudo chmod +x $NEW_SCRIPT_PATH

# Step 3: Create the new systemd service file
cat << EOF | sudo tee $NEW_SERVICE_FILE > /dev/null
[Unit]
Description=Prompt for Audirvana or Roon Server startup on TTY1 after boot
After=multi-user.target

[Service]
ExecStart=$NEW_SCRIPT_PATH
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
KillMode=process
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Step 4: Reload systemd, enable and start the new service
sudo systemctl daemon-reload
sudo systemctl enable start_audio_service_tty.service
sudo systemctl start start_audio_service_tty.service

echo "The new service has been created and started. It will prompt on TTY1 after boot."
