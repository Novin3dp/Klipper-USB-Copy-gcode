#!/bin/bash
# uninstall.sh — removes usb-gcode-copy (copied G-code files are kept)
set -e
echo "Removing usb-gcode-copy..."
sudo rm -f /etc/udev/rules.d/99-usb-gcode.rules
sudo rm -f /etc/systemd/system/usb-gcode-copy@.service
sudo rm -f /usr/local/bin/usb-gcode-copy.sh
sudo systemctl daemon-reload
sudo udevadm control --reload-rules

read -rp "Also delete the log and transfer history? [y/N]: " a
if [[ "$a" =~ ^[Yy]$ ]]; then
    sudo rm -f /var/log/usb-gcode-copy.log
    sudo rm -rf /var/lib/usb-gcode-copy
fi
sudo rmdir /media/usbgcode 2>/dev/null || true
echo "Done. Files in printer_data/gcodes/USB/ were left untouched."
