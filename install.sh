#!/usr/bin/env bash
# Offline-first installer for Novin3dp Klipper USB G-code Auto Copy.
set -Eeuo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:---offline}"

usage() {
    cat <<'EOF'
Usage:
  bash install.sh                 Install offline (default; no apt/network access)
  bash install.sh --offline       Same as above
  bash install.sh --online-deps   Install packages using apt, then install
  bash install.sh --help          Show this help

The normal installer never runs apt-get and never contacts the internet.
EOF
}

case "$MODE" in
    --offline) ;;
    --online-deps) ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $MODE"; usage; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || {
        echo "ERROR: sudo is required. Run as root or install sudo."
        exit 1
    }
    SUDO=(sudo)
fi

echo "============================================"
echo "  Novin3dp USB G-code installer"
echo "============================================"
if [ "$MODE" = "--offline" ]; then
    echo "Mode: OFFLINE (no package manager or network will be used)"
else
    echo "Mode: ONLINE (apt may access configured repositories)"
    echo "Installing curl and optional filesystem helpers..."
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y curl ntfs-3g exfatprogs
fi

# Find the Linux account that owns Klipper's gcodes directory.
KLIPPER_USER=""
for user_home in /home/*/; do
    if [ -d "${user_home}printer_data/gcodes" ]; then
        KLIPPER_USER="$(basename "$user_home")"
        break
    fi
done

if [ -z "$KLIPPER_USER" ] && [ -n "${SUDO_USER:-}" ] && [ -d "/home/$SUDO_USER/printer_data/gcodes" ]; then
    KLIPPER_USER="$SUDO_USER"
fi
if [ -z "$KLIPPER_USER" ]; then
    KLIPPER_USER="$(logname 2>/dev/null || true)"
fi
if [ -z "$KLIPPER_USER" ] || [ ! -d "/home/$KLIPPER_USER/printer_data/gcodes" ]; then
    echo "Could not automatically find the Klipper user."
    read -r -p "Enter the Klipper Linux username (for example: biqu): " KLIPPER_USER
fi
if [ ! -d "/home/$KLIPPER_USER/printer_data/gcodes" ]; then
    echo "ERROR: /home/$KLIPPER_USER/printer_data/gcodes does not exist."
    echo "Check the username and make sure Klipper is installed."
    exit 1
fi
echo "Klipper user: $KLIPPER_USER"

# curl is required at runtime. Filesystem helpers and emoji fonts are optional.
if ! command -v curl >/dev/null 2>&1; then
    echo
    echo "ERROR: curl is not installed; the copy service cannot upload files without it."
    if [ "$MODE" = "--offline" ]; then
        echo "Install curl from local/offline package media, or later run:"
        echo "  bash install.sh --online-deps"
    else
        echo "apt was unable to provide curl; check the package manager output."
    fi
    exit 1
fi

if [ "$MODE" = "--offline" ]; then
    echo "Skipping apt-get and all package downloads."
fi

echo "Installing project files..."
"${SUDO[@]}" install -D -m 755 "$SRC_DIR/usb-gcode-copy.sh" /usr/local/bin/usb-gcode-copy.sh
"${SUDO[@]}" install -D -m 644 "$SRC_DIR/usb-gcode-copy@.service" /etc/systemd/system/usb-gcode-copy@.service
"${SUDO[@]}" install -D -m 644 "$SRC_DIR/99-usb-gcode.rules" /etc/udev/rules.d/99-usb-gcode.rules

"${SUDO[@]}" sed -i "s|^USER_NAME=.*|USER_NAME=\"$KLIPPER_USER\"|" /usr/local/bin/usb-gcode-copy.sh
"${SUDO[@]}" mkdir -p /var/lib/usb-gcode-copy /media/usbgcode
"${SUDO[@]}" touch /var/log/usb-gcode-copy.log

"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" udevadm control --reload-rules

echo
echo "Checking filesystem support (informational only)..."
if grep -qw exfat /proc/filesystems 2>/dev/null || command -v mount.exfat >/dev/null 2>&1 || command -v mount.exfat-fuse >/dev/null 2>&1; then
    echo "  exFAT: kernel/helper support detected"
else
    echo "  exFAT: not detected; FAT32 will still work. Add exFAT support only if you need it."
fi
if grep -Eq '(^|[[:space:]])ntfs3?([[:space:]]|$)' /proc/filesystems 2>/dev/null || command -v mount.ntfs-3g >/dev/null 2>&1; then
    echo "  NTFS: kernel/helper support detected"
else
    echo "  NTFS: not detected; FAT32 will still work. Add NTFS support only if you need it."
fi

CFG="/home/$KLIPPER_USER/printer_data/config/printer.cfg"
MISSING=()
if [ -f "$CFG" ]; then
    grep -qE '^[[:space:]]*\[display_status\]' "$CFG" || MISSING+=("[display_status]")
    grep -qE '^[[:space:]]*\[respond\]' "$CFG" || MISSING+=("[respond]")
else
    echo "WARNING: printer.cfg was not found at $CFG"
fi
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo
    echo "WARNING: Add these missing sections to printer.cfg:"
    printf '  %s\n' "${MISSING[@]}"
    echo "Then run FIRMWARE_RESTART in Mainsail."
fi

MCFG="/home/$KLIPPER_USER/printer_data/config/moonraker.conf"
if [ -f "$MCFG" ] && grep -qE '^[[:space:]]*trusted_clients[[:space:]]*:' "$MCFG"; then
    if ! grep -Eq '^[[:space:]]*(127\.0\.0\.1|127\.0\.0\.0/8)([[:space:]]|$)' "$MCFG"; then
        echo
        echo "WARNING: trusted_clients does not visibly include 127.0.0.1 or 127.0.0.0/8."
        echo "Moonraker uploads may fail with HTTP 401/403."
    fi
fi

echo
echo "============================================"
echo "  Installation files installed successfully."
echo "============================================"
echo "Next:"
echo "  1. If printer.cfg sections were reported missing, add them and FIRMWARE_RESTART."
echo "  2. Unplug and reconnect the USB flash drive."
echo "  3. Watch the log:"
echo "     tail -f /var/log/usb-gcode-copy.log"
echo
echo "No service is enabled manually: udev starts it when a USB storage partition is inserted."
echo "Copied files are saved in: /home/$KLIPPER_USER/printer_data/gcodes/USB/"
