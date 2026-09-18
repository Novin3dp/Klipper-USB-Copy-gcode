# Novin3dp Klipper USB G-code Copy

Automatically copy G-code files from a USB flash drive into Klipper/Moonraker storage when the USB drive is plugged in.

This project follows the v2 guide: USB folders are preserved, changed files are detected with a manifest, uploads use Moonraker's file-upload API so thumbnails are available immediately, KlipperScreen shows progress, and the USB drive is mounted read-only and automatically unmounted.

## Reference hardware

Designed and tested for:

- BIGTREETECH Pi v1.2 + CB1
- MKS Robin Nano V3
- MKS TS35 V2 + KlipperScreen

## One-command installation

On the CB1/BTT Pi:

```bash
cd ~ && git clone https://github.com/Novin3dp/Klipper-USB-Copy-gcode.git && cd Klipper-USB-Copy-gcode && bash install.sh
```

If already installed:

```bash
cd ~/Klipper-USB-Copy-gcode && git pull && bash install.sh
```

The installer detects the Klipper user by looking for `printer_data/gcodes`, installs required packages, installs the udev/systemd integration, patches the user name, and checks the required Klipper/Moonraker settings.

After installation, insert a USB flash drive containing G-code files.

## Requirements

- Klipper + Moonraker + KlipperScreen
- `[display_status]` and `[respond]` in `printer.cfg`
- If Moonraker uses `trusted_clients`, `127.0.0.1` must be trusted

## How it works

```
USB inserted
    ↓
udev
    ↓
systemd usb-gcode-copy@.service
    ↓
usb-gcode-copy.sh
    ├─ read-only mount
    ├─ compare manifest
    ├─ upload through Moonraker /server/files/upload
    ├─ update KlipperScreen popup
    └─ unmount and report result
```

The design intentionally uses Moonraker's upload endpoint instead of a normal `cp`, because the guide specifies that this allows metadata and thumbnails to be generated before clients are notified.

Files are copied into:

```
~/printer_data/gcodes/USB/
```

USB subdirectories are preserved by default.

## Features

- Automatic USB detection
- Read-only mounting
- USB-only udev matching; internal mmcblk storage is not targeted
- Preserves USB folder structure
- Detects new and re-sliced/updated files
- Skips unchanged files
- Moonraker API upload for immediate metadata/thumbnail processing
- Live KlipperScreen progress popup
- Popups suppressed while printing
- Optional completion beep
- Guaranteed cleanup/unmount with `trap`
- Supports `gcode gco gc g ufp bgcode`

## Configuration

Edit the configuration block at the top of:

```
/usr/local/bin/usb-gcode-copy.sh
```

| Variable | Default | Description |
|---|---:|---|
| `SUBDIR` | `USB` | Destination subfolder inside `gcodes` |
| `KEEP_STRUCTURE` | `1` | Preserve USB folder structure |
| `BAR_W` | `14` | Progress bar width |
| `SETTLE` | `3` | Delay after USB insertion |
| `BEEP_GPIO` | empty | GPIO used for completion beep |
| `EXTENSIONS` | gcode gco gc g ufp bgcode | File extensions |

For a buzzer on GPIO70:

```bash
sudo sed -i 's|^BEEP_GPIO=.*|BEEP_GPIO="70"|' /usr/local/bin/usb-gcode-copy.sh
```

The guide notes that configuration changes are read on the next USB insertion; no service reload is required.

## Testing

Watch the log:

```bash
tail -f /var/log/usb-gcode-copy.log
```

Check services:

```journalctl -u 'usb-gcode-copy@*' -n 50 --no-pager```

Check copied files:

```
ls -la ~/printer_data/gcodes/USB/
```

## Force a full re-copy

```bash
sudo rm -f /var/lib/usb-gcode-copy/manifest
```

This clears the transfer history so files are considered again.

## Uninstall

```bash
cd ~/Klipper-USB-Copy-gcode
bash uninstall.sh
```

Copied files in `~/printer_data/gcodes/USB/` are left untouched.

## Troubleshooting

### Nothing happens

```bash
lsblk
udevadm test /sys/class/block/sda1 2>&1 | grep -i systemd
```

### HTTP 401 / 403

If Moonraker has `trusted_clients`, add `127.0.0.1`.

### HTTP 503

Moonraker/Klipper may not be ready yet, especially during boot. Reconnect the USB drive.

### Popup does not appear

Verify `[respond]` is present in `printer.cfg`. The guide provides a manual prompt test and notes that older KlipperScreen versions may not support the required client prompt behavior.

### Thumbnails are missing

Check that the slicer embedded thumbnail data:

```bash
grep -c "thumbnail begin" ~/printer_data/gcodes/USB/YOURFILE.gcode
```

Zero means the slicer needs thumbnail export enabled.

## Installed files

| Path | Purpose |
|---|---|
| `/usr/local/bin/usb-gcode-copy.sh` | Main script |
| `/etc/systemd/system/usb-gcode-copy@.service` | systemd template |
| `/etc/udev/rules.d/99-usb-gcode.rules` | USB detection |
| `/var/log/usb-gcode-copy.log` | Log |
| `/var/lib/usb-gcode-copy/manifest` | Transfer history |
| `/media/usbgcode` | Temporary mount point |

These installed paths match the v2 guide.

## License

MIT
