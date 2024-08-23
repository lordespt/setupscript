#!/bin/bash

SERVICE_FILE="/etc/systemd/system/audirvanaStudio.service"

if [ ! -f "$SERVICE_FILE" ]; then
  echo "Service file $SERVICE_FILE not found!"
  exit 1
fi

sudo sed -i '/^User=/d' "$SERVICE_FILE"

sudo systemctl daemon-reload

sudo systemctl restart audirvanaStudio

SERVICE_STATUS=$(sudo systemctl status audirvanaStudio | grep "Active:")
echo "Service status: $SERVICE_STATUS"

echo "The audirvanaStudio service has been modified to run as root and has been restarted."
