#!/usr/bin/env bash
# uninstall.sh — removes usb-gcode-copy (copied G-code files are kept)
set -euo pipefail
echo "Removing Novin3dp USB G-code Auto Copy..."

sudo systemctl stop 'usb-gcode-copy@*.service' 2>/dev/null || true
sudo rm -f /etc/udev/rules.d/99-usb-gcode.rules
sudo rm -f /etc/systemd/system/usb-gcode-copy@.service
sudo rm -f /usr/local/bin/usb-gcode-copy.sh
sudo rm -f /usr/local/lib/usb-gcode-copy-http.py
sudo systemctl daemon-reload
sudo udevadm control --reload-rules

read -r -p "Also delete the log and transfer history? [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo rm -f /var/log/usb-gcode-copy.log
    sudo rm -rf /var/lib/usb-gcode-copy
fi
sudo rmdir /media/usbgcode 2>/dev/null || true
echo "Done. Files in printer_data/gcodes/USB/ were left untouched."
