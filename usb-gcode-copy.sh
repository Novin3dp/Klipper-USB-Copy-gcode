#!/bin/bash
# usb-gcode-copy.sh
# Automatically copies G-code from a USB drive to Klipper/Moonraker.
set -u

USER_NAME="__KLIPPER_USER__"
SUBDIR="USB"
MOONRAKER="http://127.0.0.1:7125"
MNT="/media/usbgcode"
LOG="/var/log/usb-gcode-copy.log"
STATE_DIR="/var/lib/usb-gcode-copy"
BAR_W=14
KEEP_STRUCTURE=1
SETTLE=3
BEEP_GPIO=""
EXTENSIONS=(gcode gco gc g ufp bgcode)

GCODE_ROOT="/home/$USER_NAME/printer_data/gcodes"
GCODE_DIR="$GCODE_ROOT/$SUBDIR"
MANIFEST="$STATE_DIR/manifest"
DEV="/dev/${1#/dev/}"

mkdir -p "$STATE_DIR"
touch "$MANIFEST"
exec >>"$LOG" 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

rpc() {
    local out code
    out=$(curl -s -w '\n%{http_code}' -m 5 -G         --data-urlencode "script=$1"         -X POST "$MOONRAKER/printer/gcode/script")
    code=$(echo "$out" | tail -1)
    [ "$code" = "200" ] || log "gcode failed ($code): $(echo "$out" | head -1)"
}

bar() {
    local pct="$1" half full rem out="" i
    half=$((pct * BAR_W * 2 / 100))
    full=$((half / 2))
    rem=$((half % 2))
    for ((i=0; i<full; i++)); do out+="█"; done
    [ "$rem" = "1" ] && out+="▌" && full=$((full+1))
    for ((i=full; i<BAR_W; i++)); do out+="░"; done
    printf '%s %3d%%' "$out" "$pct"
}

popup() {
    [ "$SHOW" = "1" ] || return 0
    rpc 'RESPOND TYPE=command MSG="action:prompt_begin USB Transfer"'
    rpc "RESPOND TYPE=command MSG=\"action:prompt_text $1\""
    if [ -n "${2:-}" ]; then
        rpc "RESPOND TYPE=command MSG=\"action:prompt_footer_button $2|RESPOND TYPE=command MSG=action:prompt_end|primary\""
    fi
    rpc 'RESPOND TYPE=command MSG="action:prompt_show"'
}

popup_end() {
    [ "$SHOW" = "1" ] || return 0
    rpc 'RESPOND TYPE=command MSG="action:prompt_end"'
}

progress() {
    [ "$SHOW" = "1" ] || return 0
    popup_end
    popup "$1"
}

beep() {
    [ -n "$BEEP_GPIO" ] || return 0
    local g="/sys/class/gpio/gpio$BEEP_GPIO"
    [ -d "$g" ] || echo "$BEEP_GPIO" > /sys/class/gpio/export 2>/dev/null || true
    echo out > "$g/direction" 2>/dev/null || true
    echo 1 > "$g/value" 2>/dev/null || true
    sleep 0.12
    echo 0 > "$g/value" 2>/dev/null || true
}

cleanup() {
    mountpoint -q "$MNT" && umount "$MNT" && log "Unmounted $DEV"
}
trap cleanup EXIT

log "USB copy triggered for $DEV"
command -v curl >/dev/null || { log "FATAL: curl not installed"; exit 1; }
sleep "$SETTLE"

SHOW=1
STATE=$(curl -s -m 5 "$MOONRAKER/printer/objects/query?print_stats"     | grep -o '"state": *"[a-z]*"' | head -1 | cut -d'"' -f4)
log "Printer state: ${STATE:-unknown}"
if [ "$STATE" = "printing" ]; then
    SHOW=0
    log "Printing — popups suppressed"
fi

[ -b "$DEV" ] || { log "ERROR: $DEV is not a block device"; exit 1; }
mkdir -p "$MNT"

UID_N=$(id -u "$USER_NAME") || { log "ERROR: unknown user $USER_NAME"; exit 1; }
GID_N=$(id -g "$USER_NAME")

if mount -o ro,uid="$UID_N",gid="$GID_N" "$DEV" "$MNT" 2>/dev/null; then
    log "Mounted $DEV at $MNT"
elif mount -o ro "$DEV" "$MNT" 2>/dev/null; then
    log "Mounted $DEV at $MNT (without uid/gid options)"
else
    log "ERROR: failed to mount $DEV"
    exit 1
fi

FIND_EXPR=()
for e in "${EXTENSIONS[@]}"; do
    [ "${#FIND_EXPR[@]}" -gt 0 ] && FIND_EXPR+=(-o)
    FIND_EXPR+=(-iname "*.$e")
done

manifest_get() {
    awk -F'\t' -v k="$1" '$1==k {print $2"\t"$3; exit}' "$MANIFEST"
}

manifest_set() {
    local rel="$1" size="$2" mtime="$3" tmp="$MANIFEST.tmp"
    awk -F'\t' -v k="$rel" '$1!=k' "$MANIFEST" > "$tmp"
    printf '%s\t%s\t%s\n' "$rel" "$size" "$mtime" >> "$tmp"
    mv "$tmp" "$MANIFEST"
}

SRC=()
REL=()
NEW=0
UPD=0
UNCHANGED=0

while IFS= read -r -d '' f; do
    if [ "$KEEP_STRUCTURE" = "1" ]; then
        rel="${f#$MNT/}"
    else
        rel="$(basename "$f")"
    fi

    size=$(stat -c%s "$f")
    mtime=$(stat -c%Y "$f")
    rec=$(manifest_get "$rel")
    dst="$GCODE_DIR/$rel"

    if [ -f "$dst" ] && [ "$rec" = "$size	$mtime" ]; then
        UNCHANGED=$((UNCHANGED+1))
        log "unchanged: $rel"
        continue
    fi

    if [ -f "$dst" ]; then
        UPD=$((UPD+1))
    else
        NEW=$((NEW+1))
    fi
    SRC+=("$f")
    REL+=("$rel")
done < <(find "$MNT" -type f \( "${FIND_EXPR[@]}" \) -print0)

N="${#SRC[@]}"
log "To transfer: $N (new: $NEW, updated: $UPD) unchanged: $UNCHANGED"

if [ "$N" -eq 0 ]; then
    popup "ℹ️ No new or updated G-code files found." "OK"
    sleep 6
    popup_end
    exit 0
fi

popup "💾 $(bar 0)  0/$N"
OK=0
FAILED=""
i=0

for idx in "${!SRC[@]}"; do
    f="${SRC[$idx]}"
    rel="${REL[$idx]}"
    i=$((i+1))
    base="$(basename "$rel")"
    reldir="$(dirname "$rel")"

    if [ "$reldir" = "." ]; then
        upath="$SUBDIR"
    else
        upath="$SUBDIR/$reldir"
    fi

    progress "💾 $(bar $(((i-1)*100/N)))  $i/$N"
    log "uploading: $rel"

    code=$(curl -s -o /tmp/usbup.out -w '%{http_code}' -m 900         -F "root=gcodes"         -F "path=$upath"         -F "file=@$f;filename=$base"         "$MOONRAKER/server/files/upload")

    if [ "$code" = "201" ] || [ "$code" = "200" ]; then
        OK=$((OK+1))
        manifest_set "$rel" "$(stat -c%s "$f")" "$(stat -c%Y "$f")"
        log "  ok"
    else
        FAILED="$FAILED $base"
        log "  FAILED (http $code): $(head -c 300 /tmp/usbup.out 2>/dev/null)"
    fi
done

sync
progress "✅ $(bar 100)  $N/$N"
cleanup
trap - EXIT
log "Done. Uploaded $OK/$N"
beep

sleep 1
popup_end
if [ "$OK" = "$N" ]; then
    popup "✅ $OK file(s) copied. 🔌 You can remove the USB drive." "OK"
else
    popup "⚠️ $OK of $N copied. ❌ Failed:$FAILED" "OK"
fi
sleep 12
popup_end
exit 0
