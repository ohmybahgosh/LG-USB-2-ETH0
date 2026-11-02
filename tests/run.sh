#!/usr/bin/env bash
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
    LOG=$ROOT/tmp/lg-usb-2-eth0.log
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
    ln -s "$u" "$SYS/bus/usb/devices/$1"
}

# add_usb NAME PORT DRIVER CARRIER MAC [VID] [PID] [SPEED]
add_usb() {
    usbdev "$2" "${6:-0bda}" "${7:-8153}" "${8:-5000}"
    local i=$SYS/devices/usb1/$2/$2:1.0
    mkdir -p "$SYS/bus/usb/drivers/$3"
    ln -s "$SYS/bus/usb/drivers/$3" "$i/driver"
    ln -s "$SYS/bus/usb" "$i/subsystem"
    netdev "$i/net/$1" "$1" "$5" "$4"
    ln -s "$i" "$i/net/$1/device"
}

# add_wifi NAME PORT: a USB Wi-Fi module, like many LG TVs have
add_wifi() {
    add_usb "$1" "$2" mt7601u 1 "00:11:22:33:44:55" 148f 7601 480
    mkdir -p "$SYS/devices/usb1/$2/$2:1.0/net/$1/wireless"
}

# add_unclaimed PORT VID PID: a USB adapter the kernel has no driver for
add_unclaimed() { usbdev "$@"; }

# remove_usb PORT: unplug a USB device
remove_usb() {
    local u=$SYS/devices/usb1/$1 l
    for l in "$SYS/class/net"/*; do
        case "$(readlink "$l")" in "$u"/*) rm -f "$l" ;; esac
    done
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
        FAKE_STATE="$STATE" SSH_CONNECTION="${SSH_CONNECTION_TEST:-}" \
        $SH "$SCRIPT" "$@" < /dev/null > "$SB/out" 2>&1
    RC=$?
    OUT=$(cat "$SB/out")
}

# Run the installed boot hook the way the Homebrew Channel would
run_hook() {
    # shellcheck disable=SC2086 # SH is a command plus its options
    env -i HOME="$SB" PATH="$FAKEBIN:$BASE_PATH" \
        LGU2E_SYSFS="$SYS" LGU2E_SETTLE=0 LGU2E_WATCH_EVERY=1 FAKE_STATE="$STATE" \
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
    check "hook has marker" grep -q "Managed by LG-USB-2-ETH0" "$HOOK"
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
    check "hook has WATCH" grep -q '^WATCH="1"' "$HOOK"
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
    check "v1 replaced" grep -q "Managed by LG-USB-2-ETH0" "$HOOK"
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
t report test_report

[ -n "${BBDIR:-}" ] && rm -rf "$BBDIR"
echo
echo "$MODE: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || { echo "Failed:$FAILED_NAMES"; exit 1; }
