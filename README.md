# Klipper USB G-code Auto Copy

Automatic **G-code transfer from a USB flash drive to Klipper / Moonraker storage**, with KlipperScreen progress, thumbnail-aware uploads, folder preservation, and detection of new or updated files.

This project is designed for BIGTREETECH Pi / CB1 systems running Klipper, Moonraker and KlipperScreen. The installer is now **offline-first**: it does not run `apt-get update`, install packages, or access the internet.

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

Destination:

```text
~/printer_data/gcodes/USB/
```

## Reference hardware

Designed for:

- BIGTREETECH Pi v1.2 + CB1
- MKS Robin Nano V3
- MKS TS35 V2 + KlipperScreen

## Offline installation (recommended)

The easiest way to keep the CB1 offline is to download the repository ZIP on another computer and copy the extracted folder to the CB1.

1. On a computer with internet access, open the repository page and choose **Code → Download ZIP**:
   `https://github.com/Novin3dp/Klipper-USB-Copy-gcode`
2. Extract the ZIP. The folder will normally be named `Klipper-USB-Copy-gcode-main`.
3. From Windows PowerShell, copy the folder to the CB1 (replace the IP address):

```powershell
scp -r .\Klipper-USB-Copy-gcode-main biqu@<CB1_IP>:/home/biqu/
```

4. Connect to the CB1 and run:

```bash
cd ~/Klipper-USB-Copy-gcode-main
bash install.sh
```

The installer uses the Python 3 standard library and existing system utilities. It does **not** run `apt`, `apt-get update`, `git pull`, `curl`, or any download command. It only copies local project files, creates the udev rule, and installs the systemd service.

### Online clone (optional)

When the CB1 itself has working internet access, the source can also be cloned directly:

```bash
cd ~
git clone --depth 1 https://github.com/Novin3dp/Klipper-USB-Copy-gcode.git
cd Klipper-USB-Copy-gcode
bash install.sh
```

To reinstall from an already copied folder, simply run `bash install.sh` again. A `git pull` is not required for an offline reinstall; copy a newer ZIP from the computer when you need an update.

## Requirements

- Klipper + Moonraker + KlipperScreen
- Python 3 (already present on normal Klipper / CB1 images)
- systemd and udev
- `[display_status]` and `[respond]` in `printer.cfg` for KlipperScreen prompts
- If Moonraker uses `trusted_clients`, `127.0.0.1` must be trusted

The Moonraker client is implemented with Python's standard library, including streaming multipart upload, so **curl is not required**.

### USB filesystem support

The installer does not download filesystem packages. Availability depends on the CB1 kernel:

- FAT32: normally supported by the kernel.
- exFAT: requires kernel exFAT support.
- NTFS: requires the kernel `ntfs3` driver or an already installed `ntfs-3g`.

If the installer reports that a filesystem driver is missing, use a FAT32 USB drive or install that filesystem support separately when convenient. `exfatprogs` is not needed just to mount and read an exFAT drive.

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
    ├─ Python standard-library HTTP upload to Moonraker
    ├─ update KlipperScreen popup
    └─ unmount and report result
```

Moonraker's upload endpoint is used instead of a normal `cp`, so Moonraker processes the G-code and its embedded thumbnail metadata.

USB subdirectories are preserved by default.

## Features

- Automatic USB detection
- Read-only mounting
- USB-only udev matching; internal mmcblk storage is not targeted
- Preserves USB folder structure
- Detects new and re-sliced/updated files
- Skips unchanged files
- Moonraker API upload for metadata/thumbnail processing
- Live KlipperScreen progress popup
- Popups suppressed while printing
- Optional completion beep
- Guaranteed cleanup/unmount with `trap`
- Supports `gcode gco gc g ufp bgcode`

## Configuration

Edit the configuration block at the top of:

```text
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

The settings are read on the next USB insertion; no service reload is required.

## Testing

Watch the log:

```bash
tail -f /var/log/usb-gcode-copy.log
```

Check services:

```bash
systemctl status 'usb-gcode-copy@*' --no-pager
```

Check copied files:

```bash
ls -la ~/printer_data/gcodes/USB/
```

## Force a full re-copy

```bash
sudo rm -f /var/lib/usb-gcode-copy/manifest
```

This clears the transfer history so files are considered again.

## Uninstall

```bash
cd ~/Klipper-USB-Copy-gcode-main
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

Verify `[respond]` is present in `printer.cfg`. Older KlipperScreen versions may not support the required client prompt behavior.

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
| `/usr/local/lib/usb-gcode-copy-http.py` | Offline Moonraker HTTP client |
| `/etc/systemd/system/usb-gcode-copy@.service` | systemd template |
| `/etc/udev/rules.d/99-usb-gcode.rules` | USB detection |
| `/var/log/usb-gcode-copy.log` | Log |
| `/var/lib/usb-gcode-copy/manifest` | Transfer history |
| `/media/usbgcode` | Temporary mount point |

## Credits

The initial design takes inspiration from [Kanrog/klipper-usb-copy](https://github.com/Kanrog/klipper-usb-copy).

## License

MIT
