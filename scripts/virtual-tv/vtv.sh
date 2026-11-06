#!/bin/bash
# Virtual TV: a made-up LG TV on this computer, so the TV app can be shown
# and recorded without a real TV.  The app's own files run in Chromium at
# 1920x1080 (see server.js and record.js), and every command it sends to the
# Homebrew Channel runs the real LG-USB-2-ETH0.sh under busybox sh, against
# a fake /sys, fake hardware and fake TV commands (the test suite's fakes in
# tests/fakebin).  Nothing touches this computer's own network.
#
#   scripts/virtual-tv/vtv.sh setup SCENARIO   build a fresh TV, as booted
#   scripts/virtual-tv/vtv.sh exec 'COMMAND'   run a command on it
#   scripts/virtual-tv/vtv.sh stop             stop its background jobs
#   scripts/virtual-tv/vtv.sh list             the scenarios
#
# The TV lives in $VTV_DIR (default ~/.cache/lg-virtual-tv) and is rebuilt
# by every setup.  The TV app comes from webos-app/dist (webos-app/build.sh).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DIR=${VTV_DIR:-$HOME/.cache/lg-virtual-tv}
ROOT=$DIR/root
SYS=$DIR/sys
STATE=$DIR/state
APP=/media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0

scenarios() {
    cat <<'EOF'
c2        2022 C2 on webOS 25: an RTL8156 adapter on the faster driver (r8152_oot),
          with plug and unplug, Wi-Fi as a backup and update blocking on
c9        2019 C9 on webOS 4.5: an RTL8153 adapter, moved to the kernel's own
          r8152 by Realtek mode at boot
c9-fresh  the same C9 before anything is set up: the adapter on cdc_ncm
EOF
}

# ---------------------------------------------------------------- hardware

netdev() {
    mkdir -p "$1"
    echo 1 > "$1/type"; echo "$3" > "$1/address"; echo "$4" > "$1/carrier"; echo up > "$1/operstate"
    ln -s "$1" "$SYS/class/net/$2"
}

# builtin_port NAME DRIVER MAC
builtin_port() {
    local d=$SYS/devices/platform/lgeth
    mkdir -p "$d" "$SYS/bus/platform/drivers/$2"
    ln -sfn "$SYS/bus/platform/drivers/$2" "$d/driver"
    ln -sfn "$SYS/bus/platform" "$d/subsystem"
    netdev "$d/net/$1" "$1" "$3" 0
    ln -s "$d" "$d/net/$1/device"
}

# usb_nic NAME PORT DRIVER MAC VID PID CONFIG CONFIGS
usb_nic() {
    local u=$SYS/devices/usb1/$2 i=$SYS/devices/usb1/$2/$2:$7.0
    mkdir -p "$i" "$SYS/bus/usb/drivers/$3"
    echo "$5" > "$u/idVendor"; echo "$6" > "$u/idProduct"; echo 480 > "$u/speed"
    echo 1 > "$u/busnum"; echo "${2##*-}" > "$u/devnum"
    echo "$7" > "$u/bConfigurationValue"; echo "$8" > "$u/bNumConfigurations"
    ln -s "$u" "$SYS/bus/usb/devices/$2"
    ln -s "$SYS/bus/usb/drivers/$3" "$i/driver"
    ln -s "$i" "$SYS/bus/usb/drivers/$3/$2:$7.0"
    ln -s "$SYS/bus/usb" "$i/subsystem"
    echo 02 > "$i/bInterfaceClass"
    netdev "$i/net/$1" "$1" "$4" 1
    ln -s "$i" "$i/net/$1/device"
    echo "$4" > "$STATE/mac_$2"
}

# wifi NAME: the TV's own Wi-Fi module, on USB, not connected
wifi() {
    local u=$SYS/devices/usb1/1-4
    mkdir -p "$u/1-4:1.0" "$SYS/bus/usb/drivers/usb" "$SYS/bus/usb/drivers/mtk_wlan"
    echo 0e8d > "$u/idVendor"; echo 7961 > "$u/idProduct"; echo 480 > "$u/speed"
    ln -s "$u" "$SYS/bus/usb/devices/1-4"
    ln -s "$SYS/bus/usb/drivers/usb" "$u/driver"
    ln -s "$SYS/bus/usb/drivers/mtk_wlan" "$u/1-4:1.0/driver"
    netdev "$u/net/$1" "$1" "a8:23:fe:00:00:02" 0
    ln -s "$u" "$u/net/$1/device"
    mkdir -p "$u/net/$1/wireless"
}

# fake_ko FILE NAME KERNEL VID:PID...: a driver module like the ones
# get-driver downloads
fake_ko() {
    local f=$1 n=$2 k=$3 id
    shift 3
    {
        printf 'junk\0name=%s\0vermagic=%s SMP preempt mod_unload aarch64\0' "$n" "$k"
        for id in "$@"; do
            printf 'alias=usb:v%sp%sd*dc*dsc*dp*ic*isc*ip*in*\0' "$(echo "${id%:*}" | tr a-f A-F)" "$(echo "${id#*:}" | tr a-f A-F)"
        done
    } > "$f"
}

# tv KERNEL SOC MODEL RELEASE FIRMWARE BUILTIN...: the TV itself, and the
# USB network drivers its kernel has built in
tv() {
    echo "$1" > "$DIR/kernel"; echo "$2" > "$DIR/soc"; echo "$3" > "$DIR/model"; echo "$5" > "$DIR/firmware"
    mkdir -p "$ROOT/var/run/nyx" "$ROOT/lib/modules/$1"
    printf '{"webos_release":"%s","webos_manufacturing_version":"%s"}\n' "$4" "$5" > "$ROOT/var/run/nyx/os_info.json"
    local k=$1 m
    shift 5
    for m in "$@"; do
        echo "kernel/drivers/net/usb/$m.ko"
        mkdir -p "$SYS/bus/usb/drivers/$m"
    done > "$ROOT/lib/modules/$k/modules.builtin"
}

# ---------------------------------------------------------------- running

# run 'COMMAND': on the virtual TV, as root, the way the Homebrew Channel's
# exec service runs the app's commands
run() {
    local cmd=${1//$APP/$ROOT$APP}
    env -i HOME="$ROOT/home/root" PATH="$DIR/fakebin:$DIR/bb" \
        LGU2E_ROOT="$ROOT" LGU2E_SYSFS="$SYS" LGU2E_SYSWRITE="$DIR/fakebin/syswrite" FAKE_STATE="$STATE" \
        FAKE_KERNEL="$(cat "$DIR/kernel")" FAKE_SOC="$(cat "$DIR/soc")" VTV_MODEL="$(cat "$DIR/model")" VTV_FIRMWARE="$(cat "$DIR/firmware")" \
        LGU2E_SETTLE=1 LGU2E_WATCH_EVERY=2 LGU2E_NET_SETTLE=3 LGU2E_NET_CHECK=4 LGU2E_SPEED_SECS=3 \
        LGU2E_RELEASES=https://releases.test LGU2E_HOSTS="$ROOT/etc/hosts" LGU2E_BOOT_ID=vtv \
        SSH_CONNECTION="192.168.1.10 50000 192.168.1.99 22" \
        "$DIR/bb/sh" -c "$cmd"
}

stop() {
    if [ -f "$DIR/boot.pid" ]; then kill -TERM -- "-$(cat "$DIR/boot.pid")" 2>/dev/null || true; fi
    rm -f "$DIR/boot.pid"
    # Jobs the app started (apply, the watcher): their command lines name
    # the TV's folder.  Never this script or awk itself.
    ps -eo pid=,args= | awk -v r="$ROOT" -v me="$$" 'index($0, r) && $1 != me && $2 != "awk" {print $1}' | while read -r p; do
        kill "$p" 2>/dev/null || true
    done
}

# boot: what the Homebrew Channel does at startup, in its own process group
boot() {
    [ -e "$ROOT/var/lib/webosbrew/init.d/S01fix-eth" ] || return 0
    setsid "$0" exec "sh $ROOT/var/lib/webosbrew/init.d/S01fix-eth" > /dev/null 2>&1 < /dev/null &
    echo $! > "$DIR/boot.pid"
    local i=0
    while [ $i -lt 40 ] && ! grep -q 'Done: the USB adapter\|No USB Ethernet adapter' "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.log" 2>/dev/null; do
        sleep 1; i=$((i + 1))
    done
}

setup() {
    case "$1" in c2|c9|c9-fresh) ;; *) echo "Unknown scenario $1.  These exist:"; scenarios; exit 1 ;; esac
    [ -f "$REPO/webos-app/dist/index.html" ] || { echo "Build the app first: sh webos-app/build.sh" >&2; exit 1; }
    stop
    rm -rf "$DIR"
    mkdir -p "$ROOT/var/lib/webosbrew/init.d" "$ROOT/tmp" "$ROOT/etc" "$ROOT/home/root" "$STATE" "$DIR/bb" "$DIR/fakebin" \
        "$SYS/class/net" "$SYS/bus/usb/devices" "$SYS/bus/usb/drivers" "$SYS/bus/platform/drivers" "$SYS/module" \
        "$SYS/devices/usb1" "$SYS/devices/platform" "$ROOT$APP"
    # busybox, as on the TV, with the test suite's fake TV commands first
    busybox --install -s "$DIR/bb" 2>/dev/null || for a in $(busybox --list); do ln -s "$(command -v busybox)" "$DIR/bb/$a"; done
    for f in "$REPO"/tests/fakebin/*; do ln -s "$f" "$DIR/fakebin/${f##*/}"; done
    rm -f "$DIR/fakebin/luna-send" "$DIR/fakebin/uname"
    ln -s "$HERE/luna-send" "$DIR/fakebin/luna-send"
    ln -s "$HERE/uname" "$DIR/fakebin/uname"
    printf '127.0.0.1 localhost\n' > "$ROOT/etc/hosts"
    cp -R "$REPO/webos-app/dist/." "$ROOT$APP/"
    chmod 755 "$ROOT$APP/assets/lg-usb-2-eth0.sh"
    # The version in dist is the newest release, so the app offers no update
    mkdir -p "$STATE/rel"
    printf '{"id":"org.ohmybahgosh.lgusb2eth0","version":"%s","ipkUrl":"https://releases.test/x.ipk","sha256":"0"}\n' \
        "$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT$APP/assets/lg-usb-2-eth0.sh")" > "$STATE/rel/org.ohmybahgosh.lgusb2eth0.manifest.json"
    local S="sh $APP/assets/lg-usb-2-eth0.sh"
    case "$1" in
        c2)
            tv 5.4.268-329.ptl4tv.5 o22 OLED65C2PUA 10.3.1 33.30.65 r8152 asix ax88179_178a cdc_ether cdc_ncm usbnet
            builtin_port eth0 lg1k_eth a8:23:fe:00:00:01
            usb_nic eth1 1-1 cdc_ncm 00:e0:4c:68:00:01 0bda 8156 1 1
            wifi wlan0
            mkdir -p "$ROOT/home/root/lg-usb-2-eth0"
            fake_ko "$ROOT/home/root/lg-usb-2-eth0/r8152_oot.ko" r8152_oot 5.4.268-329.ptl4tv.5 0bda:8152 0bda:8153 0bda:8156
            run "$S install -y --module $ROOT/home/root/lg-usb-2-eth0/r8152_oot.ko --watch --wifi-fallback --block-updates" > /dev/null
            ;;
        c9|c9-fresh)
            tv 4.4.84-169.gld4tv.5 o18 OLED55C9PSA 4.9.0 05.50.00 r8152 asix ax88179_178a cdc_ether cdc_ncm usbnet
            builtin_port eth0 lg1k_eth a8:23:fe:00:00:01
            usb_nic eth1 1-1 cdc_ncm 00:e0:4c:68:00:02 0bda 8153 2 2
            wifi wlan0
            if [ "$1" = c9 ]; then run "$S install -y --watch" > /dev/null; fi
            ;;
    esac
    boot
    # webOS gives the adapter an address and routes through it
    echo "2: eth0 inet 192.168.1.42/24" > "$STATE/addr"
    echo 1000 > "$SYS/class/net/eth0/speed"; echo full > "$SYS/class/net/eth0/duplex"
    # Speed tests come out at what these TVs get over USB 2.0: about 280 Mbit/s
    echo 2.86 > "$STATE/speed_time"; echo DTW > "$STATE/colo"
    echo "default via 192.168.1.1 dev eth0" > "$STATE/route"
    echo "Virtual TV ready: $1 (in $DIR)"
}

case "${1:-}" in
    setup) setup "${2:?scenario}" ;;
    exec) run "${2:?command}" ;;
    stop) stop ;;
    list) scenarios ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
