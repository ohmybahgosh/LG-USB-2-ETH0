#!/usr/bin/env bash
# shellcheck disable=SC2119,SC2120 # fixture helpers take optional arguments
# Test suite for LG-USB-2-ETH0.sh
#
# Runs the script against a fake /sys and a fake `ip`, so nothing on the
# machine running the tests is touched. No root needed.
#
# Usage: tests/run.sh [busybox|dash|bash] [test name filter]
#   busybox  runs the script under busybox sh with only busybox applets on
#            PATH, which is the closest match to a webOS TV (default)
#   dash     runs it under dash
#   bash     runs it under bash in POSIX mode

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../LG-USB-2-ETH0.sh"
FAKEBIN="$HERE/fakebin"
MODE=${1:-busybox}
FILTER=${2:-}

case "$MODE" in
    busybox)
        command -v busybox >/dev/null || { echo "busybox is not installed"; exit 1; }
        BBDIR=$(mktemp -d)
        busybox --install -s "$BBDIR" 2>/dev/null || {
            for a in $(busybox --list); do ln -s "$(command -v busybox)" "$BBDIR/$a"; done
        }
        # Our fakes must win over busybox's own ip and insmod
        rm -f "$BBDIR/ip" "$BBDIR/insmod"
        BASE_PATH=$BBDIR
        SH="$(command -v busybox) sh" ;;
    dash) BASE_PATH=$PATH; SH="$(command -v dash)" ;;
    bash) BASE_PATH=$PATH; SH="$(command -v bash) --posix" ;;
    *) echo "Unknown mode: $MODE"; exit 1 ;;
esac

PASS=0
FAIL=0
FAILED_NAMES=""

# ---------------------------------------------------------------- fixtures --

new_sandbox() {
    SB=$(mktemp -d)
    ROOT=$SB/root
    SYS=$SB/sys
    STATE=$SB/state
    mkdir -p "$ROOT/var/lib/webosbrew/init.d" "$ROOT/tmp" "$STATE" \
        "$SYS/class/net" "$SYS/bus/usb/devices" "$SYS/bus/usb/drivers" \
        "$SYS/bus/platform/drivers" "$SYS/module" "$SYS/devices/usb1" "$SYS/devices/platform"
    HOOK=$ROOT/var/lib/webosbrew/init.d/S01fix-eth
    DISABLED=$ROOT/var/lib/webosbrew/S01fix-eth.disabled
    LOG=$ROOT/var/lib/webosbrew/lg-usb-2-eth0.log
    CONF=$ROOT/var/lib/webosbrew/lg-usb-2-eth0.conf
}

# netdev DIR NAME MAC CARRIER: the files every net device has
netdev() {
    mkdir -p "$1"
    echo 1 > "$1/type"
    echo "$3" > "$1/address"
    echo "$4" > "$1/carrier"
    echo up > "$1/operstate"
    ln -s "$1" "$SYS/class/net/$2"
}

# add_builtin [NAME] [CARRIER]
add_builtin() {
    local d=$SYS/devices/platform/lgeth
    mkdir -p "$d" "$SYS/bus/platform/drivers/lg-eth"
    ln -sfn "$SYS/bus/platform/drivers/lg-eth" "$d/driver"
    ln -sfn "$SYS/bus/platform" "$d/subsystem"
    netdev "$d/net/${1:-eth0}" "${1:-eth0}" "a8:23:fe:00:00:01" "${2:-0}"
    ln -s "$d" "$d/net/${1:-eth0}/device"
}

# usbdev PORT VID PID [SPEED]: a USB device and its first interface
usbdev() {
    local u=$SYS/devices/usb1/$1
    mkdir -p "$u/$1:1.0"
    echo "$2" > "$u/idVendor"
    echo "$3" > "$u/idProduct"
    echo "${4:-5000}" > "$u/speed"
    echo 1 > "$u/busnum"
    echo "${1##*-}" > "$u/devnum"
    ln -s "$u" "$SYS/bus/usb/devices/$1"
}

# add_usb NAME PORT DRIVER CARRIER MAC [VID] [PID] [SPEED]
add_usb() {
    usbdev "$2" "${6:-0bda}" "${7:-8153}" "${8:-5000}"
    local i=$SYS/devices/usb1/$2/$2:1.0
    mkdir -p "$SYS/bus/usb/drivers/$3"
    ln -s "$SYS/bus/usb/drivers/$3" "$i/driver"
    ln -s "$i" "$SYS/bus/usb/drivers/$3/$2:1.0"
    ln -s "$SYS/bus/usb" "$i/subsystem"
    netdev "$i/net/$1" "$1" "$5" "$4"
    ln -s "$i" "$i/net/$1/device"
}

# add_wifi NAME PORT: a USB Wi-Fi module, like many LG TVs have
# Like LG's own Wi-Fi: the network device hangs off the USB device itself,
# whose driver is "usb", and the real driver is on its interface.
add_wifi() {
    usbdev "$2" 148f 7601 480
    local u=$SYS/devices/usb1/$2
    mkdir -p "$SYS/bus/usb/drivers/usb" "$SYS/bus/usb/drivers/mt7601u"
    ln -s "$SYS/bus/usb/drivers/usb" "$u/driver"
    # A combo chip: Bluetooth on the first interface, Wi-Fi on the second
    mkdir -p "$u/$2:1.1" "$SYS/bus/usb/drivers/btmtk_usb"
    ln -s "$SYS/bus/usb/drivers/btmtk_usb" "$u/$2:1.0/driver"
    ln -s "$SYS/bus/usb/drivers/mt7601u" "$u/$2:1.1/driver"
    netdev "$u/net/$1" "$1" "00:11:22:33:44:55" 1
    ln -s "$u" "$u/net/$1/device"
    mkdir -p "$u/net/$1/wireless"
}

# A .ko file that declares a module name and the kernel it's built for
# fake_ko FILE NAME [KERNEL] [VID:PID...]: a fake module, optionally with the
# USB IDs it supports as aliases (like real modules have)
fake_ko() {
    local f=$1 n=$2 k=${3:-$(uname -r)} id
    shift 3 2>/dev/null || shift $#
    {
        printf 'junk\0name=%s\0vermagic=%s SMP preempt mod_unload aarch64\0' "$n" "$k"
        for id in "$@"; do
            printf 'alias=usb:v%sp%sd*dc*dsc*dp*ic*isc*ip*in*\0' "$(echo "${id%:*}" | tr a-f A-F)" "$(echo "${id#*:}" | tr a-f A-F)"
        done
    } > "$f"
}

# add_unclaimed PORT VID PID: a USB adapter the kernel has no driver for
add_unclaimed() { usbdev "$@"; }

# remove_usb PORT: unplug a USB device
remove_usb() {
    local u=$SYS/devices/usb1/$1 l
    for l in "$SYS/class/net"/*; do
        case "$(readlink "$l")" in "$u"/*) rm -f "$l" ;; esac
    done
    for l in "$SYS/bus/usb/drivers"/*/"$1":*; do [ -L "$l" ] && rm -f "$l"; done
    rm -rf "$u" "$SYS/bus/usb/devices/$1"
}

# What an interface name points at right now: builtin, usb:PORT or none
kind() {
    local t
    t=$(readlink "$SYS/class/net/$1" 2>/dev/null) || { echo none; return; }
    case "$t" in
        */platform/*) echo builtin ;;
        */usb1/*) t=${t#*/usb1/}; echo "usb:${t%%/*}" ;;
        *) echo other ;;
    esac
}

# Run the script under test
run() {
    # shellcheck disable=SC2086 # SH is a command plus its options
    env -i HOME="$SB" PATH="$FAKEBIN:$BASE_PATH" \
        LGU2E_ROOT="$ROOT" LGU2E_SYSFS="$SYS" LGU2E_SETTLE=0 LGU2E_WATCH_EVERY=1 \
        LGU2E_SYSWRITE="$FAKEBIN/syswrite" FAKE_KERNEL="${FAKE_KERNEL:-}" LGU2E_SPEED_SECS=1 LGU2E_RELEASES=https://releases.test \
        FAKE_STATE="$STATE" SSH_CONNECTION="${SSH_CONNECTION_TEST:-}" \
        $SH "$SCRIPT" "$@" < /dev/null > "$SB/out" 2>&1
    RC=$?
    OUT=$(cat "$SB/out")
}

# Run the installed boot hook the way the Homebrew Channel would
run_hook() {
    # shellcheck disable=SC2086 # SH is a command plus its options
    env -i HOME="$SB" PATH="$FAKEBIN:$BASE_PATH" LGU2E_ROOT="$ROOT" \
        LGU2E_SYSFS="$SYS" LGU2E_SETTLE=0 LGU2E_WATCH_EVERY=1 FAKE_STATE="$STATE" \
        LGU2E_SYSWRITE="$FAKEBIN/syswrite" \
        $SH "$HOOK" < /dev/null > "$SB/hook_out" 2>&1
    RC=$?
}

# wait_log PATTERN [SECONDS]: wait for the hook's log to show PATTERN
wait_log() {
    local i=0
    while [ "$i" -lt "${2:-15}" ]; do
        grep -q "$1" "$LOG" 2>/dev/null && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

stop_bg() {
    local p
    p=$(cat "$ROOT/tmp/lg-usb-2-eth0.pid" 2>/dev/null) && kill "$p" 2>/dev/null
    return 0
}

# -------------------------------------------------------------- assertions --

T_OK=1
check() {
    # check DESCRIPTION COMMAND...
    local what=$1
    shift
    if ! "$@"; then
        echo "    not ok: $what"
        T_OK=0
    fi
}
is() { [ "$(kind "$1")" = "$2" ] || { echo "    $1 is $(kind "$1"), wanted $2"; return 1; }; }
has() { case "$OUT" in *"$1"*) return 0 ;; esac; echo "    output lacks: $1"; return 1; }
lacks() { case "$OUT" in *"$1"*) echo "    output has: $1"; return 1 ;; esac; return 0; }
# json_ok JSON EXPR: JSON parses and the Python expression on it (as d) holds
json_ok() {
    printf '%s' "$1" | python3 -c 'import json, sys; d = json.loads(sys.stdin.read()); sys.exit(0 if eval(sys.argv[1]) else 1)' "$2" \
        || { echo "    json check failed: $2"; return 1; }
}
rc_is() { [ "$RC" = "$1" ] || { echo "    exit code $RC, wanted $1"; return 1; }; }

t() {
    # t NAME FUNCTION
    [ -n "$FILTER" ] && case "$1" in *"$FILTER"*) ;; *) return ;; esac
    T_OK=1
    new_sandbox
    "$2"
    stop_bg
    if [ "$T_OK" = 1 ]; then
        PASS=$((PASS + 1))
        echo "ok   $1"
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES="$FAILED_NAMES $1"
        echo "FAIL $1"
        sed 's/^/    | /' "$SB/out" 2>/dev/null | tail -n 25
        [ -f "$LOG" ] && sed 's/^/    log| /' "$LOG" | tail -n 15
    fi
    rm -rf "$SB"
}

# ------------------------------------------------------------------- tests --

test_help() {
    run --help
    check "help exits 0" rc_is 0
    check "help lists report" has "report"
    check "help lists --watch" has "--watch"
}

test_status_clean() {
    add_builtin
    run status
    check "status exits 0" rc_is 0
    check "sees built-in" has "built-in Ethernet"
    check "no hook" has "Not installed"
}

test_apply_swaps() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    check "apply exits 0" rc_is 0
    check "adapter is eth0" is eth0 usb:1-1
    check "built-in parked as eth2" is eth2 builtin
    check "says done" has "Done: the USB adapter is eth0"
}

test_apply_no_adapter() {
    add_builtin
    run apply -y
    check "built-in stays eth0" is eth0 builtin
    check "says nothing changed" has "No USB Ethernet adapter found"
}

test_revert() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    run revert -y
    check "built-in back to eth0" is eth0 builtin
    check "adapter is eth1" is eth1 usb:1-1
}

test_usb0_name() {
    add_builtin
    add_usb usb0 1-1 cdc_ether 1 "00:e0:4c:68:00:01"
    run apply -y
    check "usb0 became eth0" is eth0 usb:1-1
}

test_wifi_and_tether_ignored() {
    add_builtin
    add_wifi wlan0 1-2
    add_usb usb1 1-3 rndis_host 1 "02:00:00:00:00:01"
    run apply -y
    check "built-in stays eth0" is eth0 builtin
    check "wifi untouched" is wlan0 usb:1-2
    check "tether untouched" is usb1 usb:1-3
}

test_prefers_cable() {
    add_builtin
    add_usb eth1 1-1 r8152 0 "00:e0:4c:68:00:01"
    add_usb eth3 1-3 ax88179_178a 1 "00:0e:c6:00:00:02" 0b95 1790
    run apply -y
    check "adapter with cable wins" is eth0 usb:1-3
}

test_pin_mac() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    add_usb eth3 1-3 ax88179_178a 0 "00:0e:c6:00:00:02" 0b95 1790
    run apply -y --mac 00:0E:C6:00:00:02
    check "pinned adapter wins" is eth0 usb:1-3
    check "other adapter untouched" is eth1 usb:1-1
}

test_bad_mac() {
    run apply -y --mac nope
    check "exit 1" rc_is 1
    check "explains" has "--mac needs a MAC"
}

test_rename_retry() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    echo 2 > "$STATE/fail_rename_eth1"
    run apply -y
    check "swapped after retries" is eth0 usb:1-1
    check "built-in parked" is eth2 builtin
}

test_rename_rollback() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    echo 9 > "$STATE/fail_rename_eth1"
    run apply -y
    check "built-in back to eth0" is eth0 builtin
    check "adapter left as eth1" is eth1 usb:1-1
    check "explains" has "Putting the old names back"
}

test_builtin_rename_fails() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    echo 9 > "$STATE/fail_rename_eth0"
    run apply -y
    check "built-in stays eth0" is eth0 builtin
    check "adapter stays eth1" is eth1 usb:1-1
    check "explains" has "Nothing changed"
}

test_session_warning() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    echo "2: eth1    inet 192.168.1.20/24 brd 192.168.1.255 scope global eth1" > "$STATE/addr"
    SSH_CONNECTION_TEST="192.168.1.5 50000 192.168.1.20 22" run apply
    check "warns about the session" has "about to be renamed"
    check "cancels with no answer" has "Cancelled"
    check "nothing changed" is eth1 usb:1-1
}

test_install_and_boot() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y
    check "install exits 0" rc_is 0
    check "hook written" test -x "$HOOK"
    check "hook is a symlink" test -L "$HOOK"
    check "settings saved" grep -q "Managed by LG-USB-2-ETH0" "$CONF"
    check "not applied yet" is eth1 usb:1-1
    run_hook
    check "hook returns at once" rc_is 0
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    check "adapter is eth0" is eth0 usb:1-1
    check "built-in parked" is eth2 builtin
}

test_boot_no_adapter() {
    add_builtin
    run install -y --wait 2
    run_hook
    check "gives up quietly" wait_log "No USB Ethernet adapter after 2s"
    check "built-in stays eth0" is eth0 builtin
}

test_boot_late_adapter() {
    add_builtin
    run install -y --wait 20
    run_hook
    sleep 3
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    check "late adapter swapped" wait_log "Done: the USB adapter is eth0"
    check "adapter is eth0" is eth0 usb:1-1
}

test_watch_hotplug() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y --watch --wait 4
    check "settings have WATCH" grep -q '^WATCH="1"' "$CONF"
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    remove_usb 1-1
    check "unplug noticed" wait_log "adapter gone"
    check "built-in gets eth0 back" wait_log "the built-in port is eth0 again"
    check "built-in is eth0" is eth0 builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    check "replug noticed" wait_log "adapter eth1 appeared"
    sleep 2
    check "adapter is eth0 again" is eth0 usb:1-1
    run status
    check "status shows watch" has "keeps watching"
    check "status shows job" has "Background job running"
    run uninstall -y
    check "uninstall stops the job" has "Stopped the hook's background job"
    sleep 1
    check "job gone" sh -c "! kill -0 \$(cat '$ROOT/tmp/lg-usb-2-eth0.pid' 2>/dev/null || echo 999999) 2>/dev/null"
}

test_disable_enable() {
    add_builtin
    run install -y
    run disable
    check "hook moved out of init.d" test ! -e "$HOOK"
    check "disabled hook kept" test -f "$DISABLED"
    run status
    check "status says disabled" has "Installed but disabled"
    run enable
    check "hook back" test -x "$HOOK"
    check "disabled copy gone" test ! -e "$DISABLED"
}

test_upgrade_v1() {
    add_builtin
    printf '#!/bin/sh\nip link set eth0 down\nip link set eth0 name eth2\n' > "$HOOK"
    chmod 755 "$HOOK"
    run status
    check "status flags v1" has "Old v1 hook"
    run install -y
    check "v1 replaced by a link" test -L "$HOOK"
}

test_v1_disabled_in_initd() {
    add_builtin
    printf '#!/bin/sh\nip link set eth0 down\n' > "$HOOK.disabled"
    run status
    check "status flags it" has "may still run that file at boot"
    run disable
    check "moved out of init.d" test ! -e "$HOOK.disabled"
    check "kept outside" test -f "$DISABLED"
}

test_uninstall_now() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y --now
    check "applied now" is eth0 usb:1-1
    run uninstall -y --now
    check "hook removed" test ! -e "$HOOK"
    check "built-in back" is eth0 builtin
}

test_module_rejects_bad_path() {
    # shellcheck disable=SC2016 # the $(...) is the point of the test
    run install -y --module '/tmp/x$(reboot).ko'
    check "exit 1" rc_is 1
    check "explains" has "may only use letters"
    run install -y --module 'relative.ko'
    check "relative rejected" has "full path"
}

test_module_missing() {
    add_builtin
    run install -y --module /nonexistent/r8152.ko
    check "exit 1" rc_is 1
    check "explains" has "does not exist"
}

test_module_loaded_at_boot() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    touch "$SB/r8152.ko"
    run install -y --module "$SB/r8152.ko"
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    check "insmod called" grep -q "insmod $SB/r8152.ko" "$STATE/insmod.log"
    run status
    check "status shows module" has "loads $SB/r8152.ko"
}

test_unclaimed_adapter() {
    add_builtin
    add_unclaimed 1-4 0bda 8156
    run status
    check "spots the driverless adapter" has "no driver made a network device"
}

test_usb2_note() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01" 0bda 8153 480
    run status
    check "notes USB 2.0" has "on USB 2.0"
}

test_report() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    add_unclaimed 1-4 0b95 1790
    run report
    check "exit 0" rc_is 0
    check "fenced" has '```'
    check "masks MAC" has "00:e0:4c:xx:xx:xx"
    check "full MAC hidden" lacks "00:e0:4c:68:00:01"
    check "lists adapter id" has "id=0bda:8153"
    check "lists driverless adapter" has "no driver: 0b95:1790"
}

t help test_help
t status_clean test_status_clean
t apply_swaps test_apply_swaps
t apply_no_adapter test_apply_no_adapter
t revert test_revert
t usb0_name test_usb0_name
t wifi_and_tether_ignored test_wifi_and_tether_ignored
t prefers_cable test_prefers_cable
t pin_mac test_pin_mac
t bad_mac test_bad_mac
t rename_retry test_rename_retry
t rename_rollback test_rename_rollback
t builtin_rename_fails test_builtin_rename_fails
t session_warning test_session_warning
t install_and_boot test_install_and_boot
t boot_no_adapter test_boot_no_adapter
t boot_late_adapter test_boot_late_adapter
t watch_hotplug test_watch_hotplug
t disable_enable test_disable_enable
t upgrade_v1 test_upgrade_v1
t v1_disabled_in_initd test_v1_disabled_in_initd
t uninstall_now test_uninstall_now
t module_rejects_bad_path test_module_rejects_bad_path
t module_missing test_module_missing
t module_loaded_at_boot test_module_loaded_at_boot
t unclaimed_adapter test_unclaimed_adapter
t usb2_note test_usb2_note
drv() { kind_ok=$(nic_drv "$1"); [ "$kind_ok" = "$2" ] || { echo "    $1 driver is $kind_ok, wanted $2"; return 1; }; }
nic_drv() { local l; l=$(readlink "$SYS/class/net/$1/device/driver") && echo "${l##*/}"; }

test_takeover_apply() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    check "install exits 0" rc_is 0
    check "settings have DRIVER" grep -q '^DRIVER="r8152_oot"' "$CONF"
    run apply -y
    check "says it moved" has "cdc_ncm -> r8152_oot"
    check "now on the new driver" has "Now on r8152_oot"
    check "adapter is eth0" is eth0 usb:1-1
    check "adapter driver" drv eth0 r8152_oot
    check "built-in parked" is eth2 builtin
    check "scatter-gather off" grep -qx disable "$SYS/class/net/eth0/rtl_adv/sg_en"
    run status
    check "status lists the driver" has "r8152_oot(loaded)"
    check "status names the driver" has "(driver r8152_oot)"
}

test_takeover_boot() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    check "log shows takeover" grep -q "Now on r8152_oot" "$LOG"
    check "adapter is eth0" is eth0 usb:1-1
    check "adapter driver" drv eth0 r8152_oot
}

test_takeover_fallback() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    touch "$STATE/bind_fail"
    run install -y --module "$SB/r8152_oot.ko"
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0" 25
    check "gave it back" grep -q "Giving it back to cdc_ncm" "$LOG"
    check "adapter is eth0" is eth0 usb:1-1
    check "back on cdc_ncm" drv eth0 cdc_ncm
    run status
    check "status says still on cdc_ncm" has "still on cdc_ncm"
}

test_takeover_insmod_fails() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    touch "$STATE/insmod_fail"
    run install -y --module "$SB/r8152_oot.ko"
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "explains" grep -q "is not loaded" "$LOG"
    check "nothing unbound" sh -c "! grep -q unbind '$STATE/syswrite.log' 2>/dev/null"
    check "stays on cdc_ncm" drv eth0 cdc_ncm
}

test_module_wrong_kernel() {
    add_builtin
    fake_ko "$SB/r8152_oot.ko" r8152_oot 9.9.9-other
    run install -y --module "$SB/r8152_oot.ko"
    check "exit 1" rc_is 1
    check "explains" has "built for kernel 9.9.9-other"
    check "no hook" test ! -e "$HOOK"
}

test_get_driver_unknown_kernel() {
    add_builtin
    run get-driver -y
    check "exit 0" rc_is 0
    check "explains" has "No known better driver"
    check "nothing downloaded" test ! -e "$STATE/curl.log"
}

test_get_driver_bad_checksum() {
    add_builtin
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run get-driver -y
    check "exit 1" rc_is 1
    check "credits the author" has "github.com/DonZoomik/webos-r8152"
    check "pinned download" grep -q "raw.githubusercontent.com/DonZoomik/webos-r8152/1ea8e98" "$STATE/curl.log"
    check "explains" has "Checksum mismatch"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152_oot.ko"
    check "no partial file" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152_oot.ko.part"
}

test_status_suggests_driver() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status
    check "suggests get-driver" has "run 'get-driver'"
}

test_autobind_hook_noticed() {
    add_builtin
    ln -s /home/root/r8152-autobind.sh "$ROOT/var/lib/webosbrew/init.d/90-r8152-oot"
    run status
    check "notes the other hook" has "r8152-autobind hook is installed"
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    check "install warns" has "Keep only one"
    run status
    check "status flags both" has "both manage the driver"
}

test_wifi_driver_name() {
    add_builtin
    add_wifi wlan0 1-2
    rm -f "$SYS/class/net/wlan0/carrier"
    run status
    check "real wifi driver" has "mt7601u"
    run report
    check "carrier down" has "wifi driver=mt7601u mac=00:11:22:xx:xx:xx carrier=down"
}

test_default_route_wifi() {
    add_builtin
    add_wifi wlan0 1-2
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    echo "default via 192.168.1.1 dev wlan0" > "$STATE/route"
    run status
    check "warns traffic uses wifi" has "Traffic goes out wlan0"
    echo "default via 192.168.1.1 dev eth0" > "$STATE/route"
    run status
    check "no warning on eth0" lacks "Traffic goes out"
}

test_hook_is_link_to_copy() {
    add_builtin
    run install -y
    check "copy in /home/root" test -x "$ROOT/home/root/lg-usb-2-eth0/LG-USB-2-ETH0.sh"
    check "hook links to it" sh -c "[ \"\$(readlink '$HOOK')\" = '$ROOT/home/root/lg-usb-2-eth0/LG-USB-2-ETH0.sh' ]"
    check "copy is this version" cmp -s "$SCRIPT" "$ROOT/home/root/lg-usb-2-eth0/LG-USB-2-ETH0.sh"
}

test_install_keeps_settings() {
    add_builtin
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --watch --wait 30 --module "$SB/r8152_oot.ko"
    run install -y
    check "watch kept" grep -q '^WATCH="1"' "$CONF"
    check "wait kept" grep -q '^WAIT_SECS="30"' "$CONF"
    check "module kept" grep -q "^MODULE=\"$SB/r8152_oot.ko\"" "$CONF"
    run install -y --no-watch --no-module
    check "watch off" grep -q '^WATCH="0"' "$CONF"
    check "module off" grep -q '^MODULE=""' "$CONF"
    check "driver off" grep -q '^DRIVER=""' "$CONF"
    check "wait still kept" grep -q '^WAIT_SECS="30"' "$CONF"
}

test_upgrade_from_copied_hook() {
    add_builtin
    printf '#!/bin/sh\n# Managed by LG-USB-2-ETH0 v2.2. Change it with the LG-USB-2-ETH0 script, not by hand.\nPIN_MAC=""\nWAIT_SECS="45"\nPARK_NAME="eth2"\nMODULE=""\nDRIVER=""\nWATCH="1"\nexit 0\n' > "$HOOK"
    chmod 755 "$HOOK"
    run status
    check "still counts as enabled" has "Installed and enabled"
    check "suggests relinking" has "copy from an older version"
    check "reads its settings" has "Waits 45s"
    run install -y
    check "now a link" test -L "$HOOK"
    check "wait carried over" grep -q '^WAIT_SECS="45"' "$CONF"
    check "watch carried over" grep -q '^WATCH="1"' "$CONF"
}

test_broken_hook() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    ln -s /nonexistent/app/lg-usb-2-eth0.sh "$HOOK"
    run status
    check "flags it" has "points at a script that's gone"
    run install -y
    check "relinked" test -r "$HOOK"
}

test_invalid_settings_do_nothing() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y
    sed -i 's/^WAIT_SECS=.*/WAIT_SECS="10; reboot"/' "$CONF"
    run_hook
    check "logs it" wait_log "invalid settings" 5
    check "nothing renamed" is eth1 usb:1-1
    check "built-in untouched" is eth0 builtin
}

test_no_settings_boot_does_nothing() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y
    rm -f "$CONF"
    run_hook
    sleep 2
    check "nothing renamed" is eth1 usb:1-1
}

test_status_json() {
    add_builtin
    add_wifi wlan0 1-2
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01" 0bda 8153 480
    run install -y --watch
    run apply -y
    run status --json
    check "exit 0" rc_is 0
    printf '%s' "$OUT" > "$SB/status.json"
    check "valid JSON" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SB/status.json"
    check "adapter is eth0" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['adapterIsEth0'] is True and d['adapter']['name']=='eth0' and d['adapter']['id']=='0bda:8153' and d['adapter']['bus']=='USB 2.0'" "$SB/status.json"
    check "hook fields" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); h=d['hook']; assert h['state']=='enabled' and h['watch'] is True and h['wait']=='120'" "$SB/status.json"
    check "wifi and notes" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['wifi']['driver']=='mt7601u'; assert any('USB 2.0' in n for n in d['notes']), d['notes']" "$SB/status.json"
    check "no colour codes" lacks "$(printf '\033')"
}

test_driver_kept_after_reenumeration() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    check "on the new driver" drv eth0 r8152_oot
    check "keeps checking" wait_log "Keeping the adapter on r8152_oot"
    # TV standby resets USB: the adapter comes back, with a new device number, on cdc_ncm
    remove_usb 1-1
    add_usb eth0 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    echo 9 > "$SYS/devices/usb1/1-1/devnum"
    check "notices" wait_log "adapter is on a generic driver again" 10
    sleep 2
    check "moved back to the new driver" drv eth0 r8152_oot
    check "still eth0" is eth0 usb:1-1
    check "built-in still parked" is eth2 builtin
}

test_json_skips_p2p() {
    add_builtin
    add_wifi wlan0 1-2
    mkdir -p "$SYS/devices/usb1/1-2/net/p2p0/wireless"
    netdev "$SYS/devices/usb1/1-2/net/p2p0" p2p0 "02:11:22:33:44:55" 0
    ln -s "$SYS/devices/usb1/1-2" "$SYS/devices/usb1/1-2/net/p2p0/device"
    run status --json
    printf '%s' "$OUT" > "$SB/s.json"
    check "wlan0 chosen" python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['wifi']['name']=='wlan0'" "$SB/s.json"
}

test_boot_skips_module_for_other_kernel() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot 5.4.268-old
    # Installed while the TV ran 5.4.268-old; a firmware update changed the kernel since
    FAKE_KERNEL=5.4.268-old run install -y --module "$SB/r8152_oot.ko"
    check "installed" rc_is 0
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "explains" grep -q "built for kernel 5.4.268-old" "$LOG"
    check "never loaded" test ! -e "$STATE/insmod.log"
    check "stays on cdc_ncm" drv eth0 cdc_ncm
    run status
    check "status flags it" has "probably after a firmware update"
}

test_boot_skips_changed_module() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    check "checksum saved" grep -Eq '^MODULE_SHA="[0-9a-f]{64}"' "$CONF"
    printf 'tampered' >> "$SB/r8152_oot.ko"
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "explains" grep -q "the file changed since it was installed" "$LOG"
    check "never loaded" test ! -e "$STATE/insmod.log"
    run status
    check "status flags it" has "changed since it was installed"
    run apply -y
    check "apply won't load it either" test ! -e "$STATE/insmod.log"
}

test_speedtest() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    echo "default via 192.168.1.1 dev eth0" > "$STATE/route"
    run speedtest
    check "exit 0" rc_is 0
    check "names the interface and server" has "Speed test over eth0 (Cloudflare TST)"
    check "latency" has "Latency   12 ms"
    check "download adds the streams" has "Download  1600 Mbit/s"
    check "upload" has "Upload    1600 Mbit/s"
    check "https to Cloudflare only" sh -c "! grep -v 'https://speed.cloudflare.com/__' '$STATE/curl.log' | grep -q ."
    run report
    check "report has the speed" has "Speed:   1600 down / 1600 up Mbit/s, 12 ms, over eth0"
    run status --json
    check "status json has the speed" json_ok "$OUT" "d['speed']['downMbps'] == 1600 and d['speed']['interface'] == 'eth0'"
    run speedtest --json --phase down
    check "one phase as json" json_ok "$OUT" "d['downMbps'] == 1600 and d['upMbps'] is None and d['pingMs'] is None"
}

test_speedtest_offline() {
    add_builtin
    run speedtest
    check "exit 1 without a route" rc_is 1
    check "says why" has "no internet connection"
    echo "default via 192.168.1.1 dev eth2" > "$STATE/route"
    touch "$STATE/curl_fail"
    run speedtest
    check "exit 1 when unreachable" rc_is 1
    check "says it couldn't reach it" has "Couldn't reach"
    run status --json
    check "no speed in json" json_ok "$OUT" "d['speed'] is None"
}

# release VERSION [SCRIPT]: a fake latest release
release() {
    mkdir -p "$STATE/rel"
    printf '{\n  "id": "org.ohmybahgosh.lgusb2eth0",\n  "version": "%s",\n  "ipkUrl": "https://releases.test/download/v%s/app.ipk",\n  "ipkHash": {\n    "sha256": "%s"\n  },\n  "ipkSize": %s\n}\n' \
        "$1" "$1" "$(sha256sum "$STATE/rel/app.ipk" 2>/dev/null | awk '{print $1}')" "$( { wc -c < "$STATE/rel/app.ipk"; } 2>/dev/null | tr -d ' ')" \
        > "$STATE/rel/org.ohmybahgosh.lgusb2eth0.manifest.json"
    if [ -n "${2:-}" ]; then
        cp "$2" "$STATE/rel/LG-USB-2-ETH0.sh"
        (cd "$STATE/rel" && sha256sum LG-USB-2-ETH0.sh > SHA256SUMS)
    fi
}

test_update_check() {
    local v
    v=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SCRIPT")
    release "$v"
    run update --check --json
    check "exit 0" rc_is 0
    check "same version is not newer" json_ok "$OUT" "d['current'] == '$v' and d['latest'] == '$v' and d['newer'] is False and d['kind'] == 'script' and d['source'] == 'sideloaded'"
    run update --check
    check "says up to date" has "Up to date"
    release 2.10.0
    run update --check --json
    check "2.10 is newer than 2.3.x" json_ok "$OUT" "d['newer'] is True and d['notes'].endswith('/tag/v2.10.0')"
    mkdir -p "$ROOT/var/lib/wam/Default/Local Storage/leveldb"
    printf 'xx\001repositoriesConfig\001{"repositories":[{"url":"https://ohmybahgosh.dev/repo"}]}' \
        > "$ROOT/var/lib/wam/Default/Local Storage/leveldb/000003.log"
    run update --check --json
    check "notices the Homebrew Channel repo" json_ok "$OUT" "d['source'] == 'homebrew'"
    touch "$STATE/curl_fail"
    run update --check --json
    check "offline: exit 1" rc_is 1
    check "offline: says so" json_ok "$OUT" "d['latest'] is None and 'error' in d"
}

test_update_script() {
    cp "$SCRIPT" "$SB/copy.sh"
    sed 's/^VERSION=.*/VERSION="9.9"/' "$SCRIPT" > "$SB/new.sh"
    release 9.9.0 "$SB/new.sh"
    local SCRIPT="$SB/copy.sh"
    run update -y
    check "exit 0" rc_is 0
    check "says updated" has "Updated to 9.9.0"
    check "replaced itself" grep -q '^VERSION="9.9"' "$SB/copy.sh"
    check "still runs" sh -n "$SB/copy.sh"
    run update -y
    check "then up to date" has "Up to date (9.9)"
}

test_update_script_bad_checksum() {
    cp "$SCRIPT" "$SB/copy.sh"
    sed 's/^VERSION=.*/VERSION="9.9"/' "$SCRIPT" > "$SB/new.sh"
    release 9.9.0 "$SB/new.sh"
    echo "tampered" >> "$STATE/rel/LG-USB-2-ETH0.sh"
    local SCRIPT="$SB/copy.sh"
    run update -y
    check "exit 1" rc_is 1
    check "says mismatch" has "Checksum mismatch"
    check "left itself alone" cmp -s "$SB/copy.sh" "$HERE/../LG-USB-2-ETH0.sh"
}

test_update_app() {
    local app="$ROOT/media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0"
    mkdir -p "$app/assets"
    cp "$SCRIPT" "$app/assets/lg-usb-2-eth0.sh"
    printf '{\n  "id": "org.ohmybahgosh.lgusb2eth0",\n  "version": "2.3.0"\n}\n' > "$app/appinfo.json"
    mkdir -p "$STATE/rel"
    echo "fake ipk" > "$STATE/rel/app.ipk"
    release 2.4.0
    echo 2.4.0 > "$STATE/appver"
    local SCRIPT="$app/assets/lg-usb-2-eth0.sh"
    run update --check --json
    check "knows it's the app" json_ok "$OUT" "d['kind'] == 'app' and d['current'] == '2.3.0' and d['newer'] is True"
    run update -y
    check "exit 0" rc_is 0
    check "checked the download" has "Installing 2.4.0 now"
    local i=0
    while ! grep -q "Updated the app to 2.4.0" "$LOG" 2>/dev/null && [ $i -lt 30 ]; do sleep 0.2; i=$((i + 1)); done
    check "installed through the app installer" grep -q "appInstallService/dev/install" "$STATE/luna.log"
    check "opened the app again" grep -q "applicationManager/launch" "$STATE/luna.log"
    check "logged it" grep -q "Updated the app to 2.4.0" "$LOG"
    check "cleaned up the download" sh -c "! ls '$ROOT'/tmp/lg-usb-2-eth0-update.ipk* 2>/dev/null | grep -q ."
}

test_update_app_bad_checksum() {
    local app="$ROOT/media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0"
    mkdir -p "$app/assets" "$STATE/rel"
    cp "$SCRIPT" "$app/assets/lg-usb-2-eth0.sh"
    printf '{\n  "version": "2.3.0"\n}\n' > "$app/appinfo.json"
    echo "fake ipk" > "$STATE/rel/app.ipk"
    release 2.4.0
    echo "swapped" > "$STATE/rel/app.ipk"
    local SCRIPT="$app/assets/lg-usb-2-eth0.sh"
    run update -y
    check "exit 1" rc_is 1
    check "says mismatch" has "Checksum mismatch"
    check "never called the installer" sh -c "! grep -q dev/install '$STATE/luna.log' 2>/dev/null"
}

test_takeover_cdc_ether() {
    add_builtin
    # A kernel with no Realtek driver gives an RTL8153 to cdc_ether
    add_usb eth1 1-1 cdc_ether 1 "00:e0:4c:68:00:09" 0bda 8153 480
    fake_ko "$SB/r8152.ko" r8152 "$(uname -r)" 0bda:8152 0bda:8153
    run install -y --module "$SB/r8152.ko"
    check "install exits 0" rc_is 0
    run apply -y
    check "says it moved from cdc_ether" has "cdc_ether -> r8152"
    check "now on the new driver" has "Now on r8152"
    check "adapter is eth0" is eth0 usb:1-1
    check "adapter driver" drv eth0 r8152
}

test_takeover_only_supported_ids() {
    add_builtin
    # The module doesn't list this adapter, so it's left alone, even on cdc_ncm
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    # And a phone tethered over cdc_ether is never touched
    add_usb eth3 1-3 cdc_ether 1 "02:00:00:00:00:07" 18d1 4ee1 480
    fake_ko "$SB/r8152.ko" r8152 "$(uname -r)" 0bda:8152 0bda:8153
    run install -y --module "$SB/r8152.ko"
    run apply -y
    check "no takeover of the 2.5G adapter" lacks "cdc_ncm -> r8152"
    check "phone not unbound" sh -c "! grep -q 'cdc_ether/unbind' '$STATE/syswrite.log' 2>/dev/null"
    check "8156 still on cdc_ncm" sh -c "readlink '$SYS/devices/usb1/1-1/1-1:1.0/driver' | grep -q cdc_ncm"
}

test_driver_offer_2024() {
    add_builtin
    local k=5.4.268-294.17.paparoa.pine.2
    # No driver at all for the adapter, as on 2024 TVs where LG removed it
    add_unclaimed 1-1 0bda 8153
    FAKE_KERNEL=$k run status --json
    check "unclaimed RTL8153: available" offer_is available
    FAKE_KERNEL=$k run status
    check "status points at get-driver" has "has no driver on this TV, but one is known"
    remove_usb 1-1
    add_unclaimed 1-2 0bda 8156
    FAKE_KERNEL=$k run status --json
    check "2.5G RTL8156: not supported by that build" offer_is none
    printf 'not the module' > "$SB/r8152.ko"
    remove_usb 1-2
    add_unclaimed 1-1 0bda 8153
    FAKE_KERNEL=$k run get-driver -y --file "$SB/r8152.ko"
    check "names the 2024 build" has "mbenitez343/lg-webos-2024-ethernet-fix"
    check "says it fits the adapter" has "It supports your adapter (0bda:8153)"
    check "still refuses a wrong file" has "Checksum mismatch"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152.ko"
}

test_get_driver_download_fails() {
    add_builtin
    touch "$STATE/curl_fail"
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run get-driver -y
    check "exit 1" rc_is 1
    check "https only" grep -q -- "--proto =https" "$STATE/curl.log"
    check "explains the offline route" has "get-driver --file"
    check "mentions the clock" has "clock is right"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152_oot.ko.part"
}

test_get_driver_file_checked() {
    add_builtin
    printf 'some other file' > "$SB/r8152_oot.ko"
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run get-driver -y --file "$SB/r8152_oot.ko"
    check "exit 1" rc_is 1
    check "checksum refused" has "Checksum mismatch"
    check "no download attempted" test ! -e "$STATE/curl.log"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152_oot.ko"
}

offer_is() {
    printf '%s' "$OUT" > "$SB/o.json"
    python3 -c "import json,sys; v=json.load(open(sys.argv[1]))['driverOffer']; assert v==sys.argv[2], v" "$SB/o.json" "$1" || { echo "    driverOffer is not $1"; return 1; }
}

test_driver_offer() {
    add_builtin
    run status --json
    check "no adapter: none" offer_is none
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    run status --json
    check "other kernel: none" offer_is none
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "known kernel and Realtek: available" offer_is available
    add_usb eth3 1-3 ax88179_178a 1 "00:0e:c6:00:00:02" 0b95 1790
    remove_usb 1-1
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "known kernel but ASIX: none" offer_is none
}

test_driver_offer_states() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    run status --json
    check "set up: active" offer_is active
    FAKE_KERNEL=9.9.9 run status --json
    check "kernel changed: wrong-kernel" offer_is wrong-kernel
    printf 'x' >> "$SB/r8152_oot.ko"
    run status --json
    check "file changed: changed" offer_is changed
    rm -f "$SB/r8152_oot.ko"
    run status --json
    check "file gone: missing" offer_is missing
}

t report test_report
t takeover_apply test_takeover_apply
t takeover_boot test_takeover_boot
t takeover_fallback test_takeover_fallback
t takeover_insmod_fails test_takeover_insmod_fails
t module_wrong_kernel test_module_wrong_kernel
t get_driver_unknown_kernel test_get_driver_unknown_kernel
t get_driver_bad_checksum test_get_driver_bad_checksum
t status_suggests_driver test_status_suggests_driver
t autobind_hook_noticed test_autobind_hook_noticed
t wifi_driver_name test_wifi_driver_name
t default_route_wifi test_default_route_wifi
t speedtest test_speedtest
t speedtest_offline test_speedtest_offline
t takeover_cdc_ether test_takeover_cdc_ether
t takeover_only_supported_ids test_takeover_only_supported_ids
t driver_offer_2024 test_driver_offer_2024
t update_check test_update_check
t update_script test_update_script
t update_script_bad_checksum test_update_script_bad_checksum
t update_app test_update_app
t update_app_bad_checksum test_update_app_bad_checksum
t hook_is_link_to_copy test_hook_is_link_to_copy
t install_keeps_settings test_install_keeps_settings
t upgrade_from_copied_hook test_upgrade_from_copied_hook
t broken_hook test_broken_hook
t invalid_settings_do_nothing test_invalid_settings_do_nothing
t no_settings_boot_does_nothing test_no_settings_boot_does_nothing
t status_json test_status_json
t driver_kept_after_reenumeration test_driver_kept_after_reenumeration
t json_skips_p2p test_json_skips_p2p
t boot_skips_module_for_other_kernel test_boot_skips_module_for_other_kernel
t boot_skips_changed_module test_boot_skips_changed_module
t get_driver_download_fails test_get_driver_download_fails
t get_driver_file_checked test_get_driver_file_checked
t driver_offer test_driver_offer
t driver_offer_states test_driver_offer_states

[ -n "${BBDIR:-}" ] && rm -rf "$BBDIR"
echo
echo "$MODE: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || { echo "Failed:$FAILED_NAMES"; exit 1; }
