#!/bin/sh
# Audit one LG TV firmware file for USB Ethernet drivers, then clean up.
#
# Usage: scripts/firmware-audit/audit.sh FIRMWARE.zip|FIRMWARE.epk [MODEL]
#
# Unpacks the firmware with epk2extract (https://github.com/openlgtv/epk2extract,
# set EPK2EXTRACT to its build_linux/epk2extract) and prints one
# tab-separated line:
#
#   model  firmware  chip  platform  kernel  built-in  modules  source
#
# kernel is the exact name `uname -r` prints on that TV.  built-in lists the
# USB network drivers compiled into the kernel, and modules the ones built as
# loadable modules.  source says where that came from: the kernel's own
# config (when the firmware has a kernel image with one built in), or the
# root filesystem's lib/modules (when the update only carries the rootfs).
#
# Everything it unpacked, and the firmware file itself, is deleted
# afterwards.  Set KEEP=1 to keep the firmware file.  Needs python3 and
# unsquashfs (squashfs-tools).
set -eu

FW=$1
MODEL=${2:-}
EPK2EXTRACT=${EPK2EXTRACT:-$HOME/lg-fw-audit/epk2extract/build_linux/epk2extract}
[ -x "$EPK2EXTRACT" ] || { echo "epk2extract not found at $EPK2EXTRACT (set EPK2EXTRACT)" >&2; exit 1; }
command -v unsquashfs >/dev/null || { echo "unsquashfs is missing (squashfs-tools)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/lg-fw-audit.XXXXXX")
cleanup() {
    rm -rf "$WORK"
    [ "${KEEP:-0}" = 1 ] || rm -f "$FW"
}
trap cleanup EXIT INT TERM

case "$FW" in
    *.zip) unzip -q -o "$FW" -d "$WORK/zip"; EPK=$(find "$WORK/zip" -name '*.epk' | head -n 1) ;;
    *) EPK=$FW ;;
esac
[ -n "$EPK" ] && [ -f "$EPK" ] || { echo "no .epk in $FW" >&2; exit 1; }
NAME=$(basename "$EPK")

# epk2extract writes next to the file it reads, so give it one inside the
# work folder.  It looks for its keys next to itself.
case "$EPK" in "$WORK"/*) ;; *) ln -s "$(cd "$(dirname "$EPK")" && pwd)/$NAME" "$WORK/$NAME"; EPK=$WORK/$NAME ;; esac
( cd "$(dirname "$EPK2EXTRACT")" && "$EPK2EXTRACT" "$EPK" > "$WORK/extract.log" 2>&1 ) || true

KERNEL="" BUILTIN="" MODULES="" SOURCE=""
# The USB network drivers that matter for Ethernet adapters (kernel-info.py
# lists the same ones)
WANT='r8152|r8153_ecm|asix|ax88179_178a|cdc_ether|cdc_ncm|cdc_eem|smsc95xx|smsc75xx|lan78xx|aqc111|dm9601|rtl8150|usbnet'

# 1. The kernel image, when the firmware has one: its version string, and the
#    config built into it (CONFIG_IKCONFIG)
KIMG=$(find "$WORK" -name 'kernel.pak.unlz4' | head -n 1)
[ -n "$KIMG" ] || KIMG=$(find "$WORK" -name 'kernel.pak' | head -n 1)
if [ -n "$KIMG" ]; then
    _out=$(python3 "$HERE/kernel-info.py" "$KIMG" 2>/dev/null || true)
    KERNEL=$(echo "$_out" | sed -n 's/^kernel=//p')
    BUILTIN=$(echo "$_out" | sed -n 's/^builtin=//p')
    MODULES=$(echo "$_out" | sed -n 's/^modules=//p')
    [ -n "$(echo "$_out" | sed -n 's/^config=//p')" ] && SOURCE=config
fi

# 2. Otherwise the rootfs: lib/modules/<kernel>/modules.builtin and the .ko files
#    (usr/lib/modules from webOS 26 on)
if [ -z "$SOURCE" ]; then
    ROOTFS=$(find "$WORK" -name rootfs.pak | head -n 1)
    if [ -n "$ROOTFS" ]; then
        unsquashfs -q -n -d "$WORK/rfs" "$ROOTFS" lib/modules usr/lib/modules > /dev/null 2>&1 || true
        _b=$(find "$WORK/rfs" -path '*/lib/modules/*' -name modules.builtin 2>/dev/null | head -n 1)
        if [ -n "$_b" ]; then
            _k=$(dirname "$_b")
            [ -n "$KERNEL" ] || KERNEL=${_k##*/}
            BUILTIN=$(grep -E '/net/usb/' "$_b" | sed 's#.*/##; s#\.ko$##' | grep -x -E "$WANT" | sort | tr '\n' ' ' | sed 's/ $//')
            MODULES=$(find "$_k" -path '*/net/usb/*.ko*' | sed 's#.*/##; s#\.ko.*$##' | grep -x -E "$WANT" | sort | tr '\n' ' ' | sed 's/ $//')
            SOURCE=modules.builtin
        fi
    fi
fi
if [ -z "$KERNEL" ]; then
    echo "$NAME: no kernel image or lib/modules found.  Parts it has:" >&2
    find "$WORK" -name '*.pak' -exec basename {} \; | sort | tr '\n' ' ' >&2
    echo >&2
fi

# The firmware name says the chip and platform, like
# lib32-starfish-global-secured-o22-papikonda-3006-33.31.68_prodkey_...epk
CHIP=$(echo "$NAME" | sed -n 's/.*-secured-\([a-z0-9_]*\)-.*/\1/p')
PLATFORM=$(echo "$NAME" | sed -n 's/.*-secured-[a-z0-9_]*-\([a-z0-9]*\)-.*/\1/p')
VER=$(echo "$NAME" | sed -n 's/.*-\([0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{2\}\)_.*/\1/p')

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${MODEL:--}" "${VER:--}" "${CHIP:--}" "${PLATFORM:--}" \
    "${KERNEL:-unknown}" "${BUILTIN:-none}" "${MODULES:-none}" "${SOURCE:--}"
