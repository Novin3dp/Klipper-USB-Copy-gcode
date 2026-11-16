# Klipper USB G-code Auto Copy

Automatic **G-code transfer from a USB flash drive to Klipper / Moonraker storage**, with KlipperScreen progress, thumbnail-aware uploads, folder preservation, and detection of new or updated files.

The installer is **offline-first**: the normal installation does not run `apt-get`, download packages, clone repositories, or require an internet connection. Download the project ZIP on another computer, transfer it to the printer, extract it, and run the installer.

## What it does

Insert a USB flash drive containing G-code files and the system automatically:

- Detects the USB storage device.
- Mounts the USB filesystem **read-only**.
- Preserves the USB folder structure.
- Detects new files and re-sliced/updated files.
- Uploads files through Moonraker `/server/files/upload`.
- Shows transfer progress through a KlipperScreen prompt.
- Optionally beeps when the transfer finishes.
- Cleans up and unmounts the USB drive on exit.

Destination: `~/printer_data/gcodes/USB/`

## Quick offline installation (recommended)

### 1. Download the ZIP on a computer with internet

Open the [GitHub repository](https://github.com/Novin3dp/Klipper-USB-Copy-gcode), choose **Code → Download ZIP**, and save the ZIP file. Do not extract it yet.

### 2. Transfer the ZIP to the BTT Pi / CB1

From Windows PowerShell, replace the IP address if needed:

```powershell
scp "$env:USERPROFILE\Downloads\Klipper-USB-Copy-gcode-main.zip" biqu@PRINTER_IP:/home/biqu/
```

Accept the SSH fingerprint with `yes` if prompted, then enter the Linux user's password. Password characters are not shown while typing.

### 3. Extract and install on the printer

Connect by SSH, then run:

```bash
cd ~
unzip -o Klipper-USB-Copy-gcode-main.zip
rm -rf ~/Klipper-USB-Copy-gcode
mv ~/Klipper-USB-Copy-gcode-main ~/Klipper-USB-Copy-gcode
cd ~/Klipper-USB-Copy-gcode
bash install.sh
```

The installer automatically detects the Klipper Linux user (for example, `biqu`), copies the service and udev files, patches the username, creates required directories, and reloads systemd/udev.

**Important:** `bash install.sh` is offline by default. It does not run `apt-get update` or install packages.

### 4. Check Klipper settings

The installer checks for these sections in `~/printer_data/config/printer.cfg`:

```ini
[display_status]

[respond]
```

If it reports either section missing, add only the missing section(s), save the file, and click **FIRMWARE RESTART** in Mainsail.

If Moonraker has a `trusted_clients` list, it must allow localhost. The following is valid:

```ini
trusted_clients:
    127.0.0.0/8
```

### 5. Test

Unplug and reconnect the USB flash drive. Watch the log:

```bash
tail -f /var/log/usb-gcode-copy.log
```

Copied files appear in:

```bash
ls -la ~/printer_data/gcodes/USB/
```

## Installation modes

| Command | Behavior |
|---|---|
| `bash install.sh` | Offline installation; no package manager or network access |
| `bash install.sh --offline` | Same as the default |
| `bash install.sh --online-deps` | Uses apt to install curl, ntfs-3g, and exfatprogs, then installs the project |
| `bash install.sh --help` | Shows installer help |

Only `curl` is a required external runtime package. The installer checks for it and stops with an actionable message if it is missing. `exfatprogs` is not required merely to mount an exFAT drive; actual exFAT/NTFS mounting depends on kernel or filesystem-helper support. FAT32 is the safest choice when preparing a USB drive for a system with unknown filesystem support. The emoji font is optional.

## Reference hardware

Designed and tested for:

- BIGTREETECH Pi v1.2 + CB1
- MKS Robin Nano V3
- MKS TS35 V2 + KlipperScreen

## Requirements

- Klipper + Moonraker + KlipperScreen
- `curl`
- `[display_status]` and `[respond]` in `printer.cfg`
- If Moonraker uses `trusted_clients`, localhost (`127.0.0.1` or `127.0.0.0/8`) must be trusted

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

The design uses Moonraker's upload endpoint instead of a normal `cp`, so metadata and thumbnails can be processed before clients are notified.

## Configuration

Edit the configuration block at the top of `/usr/local/bin/usb-gcode-copy.sh`.

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

Configuration changes are read on the next USB insertion; no service reload is required.

## Testing and maintenance

Watch the log:

```bash
tail -f /var/log/usb-gcode-copy.log
```

Check service logs:

```bash
journalctl -u 'usb-gcode-copy@*' -n 50 --no-pager
```

Force a full re-copy:

```bash
sudo rm -f /var/lib/usb-gcode-copy/manifest
```

Uninstall:

```bash
cd ~/Klipper-USB-Copy-gcode
bash uninstall.sh
```

Copied files in `~/printer_data/gcodes/USB/` are left untouched.

## Troubleshooting

### Nothing happens

```bash
lsblk
journalctl -u 'usb-gcode-copy@*' -n 50 --no-pager
```

### HTTP 401 / 403

If Moonraker has `trusted_clients`, allow localhost, for example `127.0.0.0/8`.

### HTTP 503

Moonraker/Klipper may not be ready yet, especially during boot. Reconnect the USB drive.

### Popup does not appear

Verify `[respond]` is present in `printer.cfg`, then run **FIRMWARE RESTART**. Older KlipperScreen versions may not support the required client prompt behavior.

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

## Credits

The initial design includes ideas inspired by [Kanrog/klipper-usb-copy](https://github.com/Kanrog/klipper-usb-copy).

## License

MIT
