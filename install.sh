#!/bin/bash
# install.sh — automatic installer for Novin3dp usb-gcode-copy
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Novin3dp usb-gcode-copy installer"
echo "============================================"

# Detect the Klipper Linux user by finding printer_data/gcodes.
KLIPPER_USER=""
for user_home in /home/*/; do
    if [ -d "${user_home}printer_data/gcodes" ]; then
        KLIPPER_USER="$(basename "$user_home")"
        break
    fi
done

if [ -z "$KLIPPER_USER" ]; then
    KLIPPER_USER="$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")"
fi

if [ ! -d "/home/$KLIPPER_USER/printer_data/gcodes" ]; then
    echo "Could not find printer_data/gcodes for '$KLIPPER_USER'."
    read -rp "Enter the Klipper username manually: " KLIPPER_USER
    [ -d "/home/$KLIPPER_USER/printer_data/gcodes" ] || {
        echo "Directory /home/$KLIPPER_USER/printer_data/gcodes does not exist."
        exit 1
    }
fi

echo "→ Klipper user: $KLIPPER_USER"

echo "→ Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl exfatprogs ntfs-3g fonts-noto-color-emoji
fc-cache -f >/dev/null 2>&1 || true

echo "→ Installing files..."
sudo install -m 755 "$SRC_DIR/usb-gcode-copy.sh" /usr/local/bin/usb-gcode-copy.sh
sudo install -m 644 "$SRC_DIR/usb-gcode-copy@.service" /etc/systemd/system/usb-gcode-copy@.service
sudo install -m 644 "$SRC_DIR/99-usb-gcode.rules" /etc/udev/rules.d/99-usb-gcode.rules

sudo sed -i "s|^USER_NAME=.*|USER_NAME=\"$KLIPPER_USER\"|" /usr/local/bin/usb-gcode-copy.sh

sudo mkdir -p /var/lib/usb-gcode-copy /media/usbgcode
sudo touch /var/log/usb-gcode-copy.log

sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block >/dev/null 2>&1 || true

CFG="/home/$KLIPPER_USER/printer_data/config/printer.cfg"
NEED=""
if [ -f "$CFG" ]; then
    grep -qE '^[[:space:]]*\[display_status\]' "$CFG" || NEED="$NEED [display_status]"
    grep -qE '^[[:space:]]*\[respond\]' "$CFG" || NEED="$NEED [respond]"
else
    echo "!! printer.cfg was not found at $CFG"
fi

if [ -n "$NEED" ]; then
    echo
    echo "!! printer.cfg is missing:$NEED"
    echo "   Add the missing sections and run FIRMWARE_RESTART."
fi

MCFG="/home/$KLIPPER_USER/printer_data/config/moonraker.conf"
if [ -f "$MCFG" ] && grep -q 'trusted_clients' "$MCFG"; then
    if ! grep -q '127\.0\.0\.1' "$MCFG"; then
        echo
        echo "!! moonraker.conf has trusted_clients but no 127.0.0.1 entry."
        echo "   Uploads may fail with HTTP 401/403."
    fi
fi

echo
echo "============================================"
echo "  Installation complete."
echo "  Plug in a USB drive to test."
echo "  Log: tail -f /var/log/usb-gcode-copy.log"
echo "============================================"
