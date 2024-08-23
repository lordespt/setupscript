#!/bin/bash

SCRIPT_PATH="/usr/local/bin/start_audio_service.sh"

cat << 'EOF' | sudo tee $SCRIPT_PATH > /dev/null
#!/bin/bash

read -t 60 -p "Which service would you like to start? (audirvana/roon): " SERVICE

if [ -z "$SERVICE" ]; then
  SERVICE="roon"
fi

case $SERVICE in
  audirvana)
    echo "Starting Audirvana Studio..."
    systemctl start audirvanaStudio.service
    ;;
  roon)
    echo "Starting Roon Server..."
    systemctl start roonserver.service
    ;;
  *)
    echo "Invalid selection. Defaulting to Roon Server..."
    systemctl start roonserver.service
    ;;
esac
EOF

sudo chmod +x $SCRIPT_PATH

SERVICE_FILE="/etc/systemd/system/start_audio_service.service"

cat << EOF | sudo tee $SERVICE_FILE > /dev/null
[Unit]
Description=Start either Audirvana or Roon server at startup
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable start_audio_service.service

sudo systemctl start start_audio_service.service

echo "Service has been created and started. It will now ask which service to start on boot."
