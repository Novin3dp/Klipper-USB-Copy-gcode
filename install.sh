#!/usr/bin/env bash
# Offline-first installer for Novin3dp USB G-code Auto Copy.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Novin3dp USB G-code Auto Copy installer"
echo "  Offline-first / no package downloads"
echo "============================================"

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Run this installer as the normal Klipper user (for example: biqu), not root."
    exit 1
fi

for cmd in sudo python3 systemctl udevadm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command is missing: $cmd"
        echo "No packages were installed. This installer does not download dependencies."
        exit 1
    fi
done

echo "→ Administrator permission is required for system files."
echo "  Enter the Linux password for user '$USER' (password typing is hidden)."
if ! sudo -v; then
    echo "ERROR: sudo authentication failed. Check the Linux account password and sudo permissions."
    exit 1
fi
echo "  ✓ Administrator permission confirmed."

# Detect the Klipper Linux user by finding printer_data/gcodes.
KLIPPER_USER=""
for user_home in /home/*/; do
    if [[ -d "${user_home}printer_data/gcodes" ]]; then
        KLIPPER_USER="$(basename "$user_home")"
        break
    fi
done

if [[ -z "$KLIPPER_USER" ]]; then
    KLIPPER_USER="${SUDO_USER:-$USER}"
fi

if [[ ! -d "/home/$KLIPPER_USER/printer_data/gcodes" ]]; then
    echo "Could not find printer_data/gcodes for '$KLIPPER_USER'."
    read -r -p "Enter the Klipper username manually: " KLIPPER_USER
    [[ -d "/home/$KLIPPER_USER/printer_data/gcodes" ]] || {
        echo "Directory /home/$KLIPPER_USER/printer_data/gcodes does not exist."
        exit 1
    }
fi

echo "→ Klipper user: $KLIPPER_USER"
echo "→ Python: $(python3 --version)"
echo "→ Checking local USB filesystem support..."

if grep -qw vfat /proc/filesystems; then
    echo "  ✓ FAT32 support available"
else
    echo "  ! FAT32 kernel support was not detected"
fi
if grep -qw exfat /proc/filesystems; then
    echo "  ✓ exFAT kernel support available"
else
    echo "  ! exFAT kernel support not detected; FAT32 USB drives will still work"
    echo "    No exfatprogs package will be downloaded or installed."
fi
if grep -qw ntfs3 /proc/filesystems || command -v ntfs-3g >/dev/null 2>&1; then
    echo "  ✓ NTFS support available"
else
    echo "  ! NTFS support not detected; use FAT32/exFAT or install NTFS support separately"
fi

echo "→ Installing project files (no apt, no internet access)..."
sudo install -d -m 755 /usr/local/bin /usr/local/lib
sudo install -m 755 "$SRC_DIR/usb-gcode-copy.sh" /usr/local/bin/usb-gcode-copy.sh
sudo install -m 755 "$SRC_DIR/usb-gcode-copy-http.py" /usr/local/lib/usb-gcode-copy-http.py
sudo install -m 644 "$SRC_DIR/usb-gcode-copy@.service" /etc/systemd/system/usb-gcode-copy@.service
sudo install -m 644 "$SRC_DIR/99-usb-gcode.rules" /etc/udev/rules.d/99-usb-gcode.rules

sudo sed -i "s|^USER_NAME=.*|USER_NAME=\"$KLIPPER_USER\"|" /usr/local/bin/usb-gcode-copy.sh

sudo install -d -m 755 /var/lib/usb-gcode-copy /media/usbgcode
sudo touch /var/lib/usb-gcode-copy/manifest /var/log/usb-gcode-copy.log
sudo chmod 644 /var/lib/usb-gcode-copy/manifest /var/log/usb-gcode-copy.log

sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block --action=add >/dev/null 2>&1 || true

CFG="/home/$KLIPPER_USER/printer_data/config/printer.cfg"
NEED=""
if [[ -f "$CFG" ]]; then
    grep -qE '^[[:space:]]*\[display_status\]' "$CFG" || NEED="$NEED [display_status]"
    grep -qE '^[[:space:]]*\[respond\]' "$CFG" || NEED="$NEED [respond]"
else
    echo "!! printer.cfg was not found at $CFG"
fi

if [[ -n "$NEED" ]]; then
    echo
    echo "!! printer.cfg may be missing:$NEED"
    echo "   Add the missing sections (or confirm they are supplied by included files) and run FIRMWARE_RESTART."
fi

MCFG="/home/$KLIPPER_USER/printer_data/config/moonraker.conf"
if [[ -f "$MCFG" ]] && grep -q 'trusted_clients' "$MCFG"; then
    if ! grep -q '127\.0\.0\.1' "$MCFG"; then
        echo
        echo "!! moonraker.conf has trusted_clients but no 127.0.0.1 entry."
        echo "   Local uploads may fail with HTTP 401/403."
    fi
fi

echo
echo "============================================"
echo "  Installation complete."
echo "  No package manager or network was used."
echo "  Plug in a USB drive to test."
echo "  Log: tail -f /var/log/usb-gcode-copy.log"
echo "============================================"
