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

# add_virtual_builtin [NAME]: the built-in port as some Realtek-chip TVs show
# it (a UN7300 on webOS 5, issue #6), with no parent device
add_virtual_builtin() {
    netdev "$SYS/devices/virtual/net/${1:-eth0}" "${1:-eth0}" "b4:b2:91:00:00:01" 0
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
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi
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
        */virtual/net/*) echo virtual ;;
        */usb1/*) t=${t#*/usb1/}; echo "usb:${t%%/*}" ;;
        *) echo other ;;
    esac
}

# Run the script under test
run() {
    # shellcheck disable=SC2086 # SH is a command plus its options
    env -i HOME="$SB" PATH="$FAKEBIN:$BASE_PATH" \
        LGU2E_ROOT="$ROOT" LGU2E_SYSFS="$SYS" LGU2E_SETTLE=0 LGU2E_WATCH_EVERY=1 \
        LGU2E_SYSWRITE="$FAKEBIN/syswrite" FAKE_KERNEL="${FAKE_KERNEL:-}" FAKE_SOC="${FAKE_SOC:-}" LGU2E_TEST_DRIVER="${LGU2E_TEST_DRIVER:-}" LGU2E_TEST_EXPERIMENTAL="${LGU2E_TEST_EXPERIMENTAL:-}" LGU2E_TEST_TESTED="${LGU2E_TEST_TESTED:-}" LGU2E_TEST_USBNET="${LGU2E_TEST_USBNET:-}" LGU2E_REALTEK_MODE="${LGU2E_REALTEK_MODE:-}" LGU2E_BOOT_ID="${FAKE_BOOT_ID:-boot1}" LGU2E_NET_CHECK=4 LGU2E_SPEED_SECS=1 LGU2E_RELEASES=https://releases.test \
        FAKE_STATE="$STATE" SSH_CONNECTION="${SSH_CONNECTION_TEST:-}" LGU2E_HOSTS="$SB/hosts" \
        LGU2E_APP_FIRMWARE="${APP_FIRMWARE:-}" LGU2E_APP_MODEL="${APP_MODEL:-}" LGU2E_APP_BOARD="${APP_BOARD:-}" LGU2E_APP_LANG="${APP_LANG:-}" \
        $SH "$SCRIPT" "$@" < /dev/null > "$SB/out" 2>&1
    RC=$?
    OUT=$(cat "$SB/out")
}

# Run the installed boot hook the way the Homebrew Channel would
run_hook() {
    # shellcheck disable=SC2086 # SH is a command plus its options
    env -i HOME="$SB" PATH="$FAKEBIN:$BASE_PATH" LGU2E_ROOT="$ROOT" \
        LGU2E_SYSFS="$SYS" LGU2E_SETTLE=0 LGU2E_WATCH_EVERY=1 FAKE_STATE="$STATE" LGU2E_HOSTS="$SB/hosts" \
        LGU2E_SYSWRITE="$FAKEBIN/syswrite" LGU2E_WIFI_GRACE=3 LGU2E_WIFI_BACK=2 \
        LGU2E_NET_SETTLE=2 LGU2E_NET_CHECK=3 LGU2E_HANG_SECS=3 \
        LGU2E_REALTEK_MODE="${LGU2E_REALTEK_MODE:-}" LGU2E_TEST_USBNET="${LGU2E_TEST_USBNET:-}" $SH "$HOOK" < /dev/null > "$SB/hook_out" 2>&1
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
drv() { kind_ok=$(nic_drv "$1"); [ "$kind_ok" = "$2" ] || { echo "    $1 driver is $kind_ok, wanted $2"; return 1; }; }
nic_drv() { local l; l=$(readlink "$SYS/class/net/$1/device/driver") && echo "${l##*/}"; }
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

test_apply_virtual_builtin() {
    add_virtual_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    check "apply exits 0" rc_is 0
    check "adapter is eth0" is eth0 usb:1-1
    check "virtual built-in parked as eth2" is eth2 virtual
    run report
    check "report lists the parked virtual port" has "eth2 builtin driver=virtual"
    run status
    check "status lists it as built-in" has "built-in Ethernet"
    run revert -y
    check "built-in back to eth0" is eth0 virtual
    check "adapter is eth1" is eth1 usb:1-1
}

test_apply_virtual_bridge_left_alone() {
    add_virtual_builtin
    mkdir -p "$SYS/devices/virtual/net/eth0/bridge"
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run apply -y
    check "a bridge called eth0 is left alone" has "eth0 is not the built-in port"
    check "adapter stays eth1" is eth1 usb:1-1
}

# The app passes what the TV told it when the script's own commands come
# back empty under the Homebrew Channel (issue #6)
test_app_tv_info() {
    add_builtin
    APP_FIRMWARE=04.50.56 APP_MODEL=55UN7300AUD APP_BOARD=K6LP_ATSC_US run report
    check "firmware from the app" has "04.50.56"
    check "chip from the board type" has "Chip:    k6lp"
    # shellcheck disable=SC2016 # a literal \$(x), the kind of value to refuse
    APP_FIRMWARE='04.50;reboot' APP_BOARD='K6LP$(x)' run report
    check "odd values ignored" lacks "reboot"
    check "odd board ignored" lacks "k6lp"
}

# Once the adapter is eth0, status says how the TV can be woken over the
# network: standby resets the USB ports, so through Wi-Fi or a cabled
# built-in port
test_wake_path() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    add_wifi wlan0 1-2
    run apply -y
    run status
    check "wake through Wi-Fi" has "goes through Wi-Fi, not the adapter"
    check "names the Wi-Fi MAC" has "00:11:22:33:44:55"
    run report
    check "report: wifi" has "Wake over network: wifi"
    echo 0 > "$SYS/class/net/wlan0/carrier"
    run status
    check "nothing can wake it" has "Nothing can turn the TV on over the network"
    echo 1 > "$SYS/class/net/eth2/carrier"
    run report
    check "report: builtin" has "Wake over network: builtin"
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

# A hung adapter (cable link up, sending, nothing back) is re-plugged in
# software once, then made eth0 again
test_watch_hung_adapter() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y --watch --wait 4
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    local st=$SYS/class/net/eth0/statistics i=0
    mkdir -p "$st"
    echo 100 > "$st/rx_packets"
    check "watching" wait_log "Watching for the adapter" 20
    sleep 2
    # Receiving and sending: not hung
    while [ $i -lt 6 ]; do echo $((100 + i)) > "$st/rx_packets"; echo $((50 + i)) > "$st/tx_packets"; sleep 1; i=$((i + 1)); done
    check "a working link is left alone" sh -c "! grep -q 'seems hung' '$LOG'"
    # Sending, nothing back
    i=0
    while [ $i -lt 15 ] && ! grep -q 'seems hung' "$LOG"; do echo $((60 + i)) > "$st/tx_packets" 2>/dev/null; sleep 1; i=$((i + 1)); done
    check "hang noticed" wait_log "the adapter seems hung"
    check "re-plugged in software" grep -q "1-1/authorized 0" "$STATE/syswrite.log"
    check "says so on screen" wait_log "(shown on the TV) the USB adapter stopped answering"
    check "through webOS's notifications" grep -q "createToast.*stopped answering" "$STATE/luna.log"
    check "adapter is eth0" is eth0 usb:1-1
    stop_bg
}

# link NAME SPEED [DUPLEX]: what the cable negotiated
link() { echo "$2" > "$SYS/class/net/$1/speed"; echo "${3:-full}" > "$SYS/class/net/$1/duplex"; }

test_link_speed() {
    add_builtin eth2
    add_usb eth0 1-1 r8152 1 "00:e0:4c:68:00:01" 0bda 8153 480
    link eth0 1000
    run status
    lacks "cable link is only"
    lacks "half duplex"
    link eth0 100
    run status
    check "100 Mbit/s link flagged" has "eth0's cable link is only 100 Mbit/s"
    check "says what to try" has "Cat5e"
    run status --json
    check "json has speed and duplex" json_ok "$OUT" "d['adapter']['speed'] == 100 and d['adapter']['duplex'] == 'full' and any('100 Mbit/s' in i for i in d['issues'])"
    link eth0 1000 half
    run status
    check "half duplex flagged" has "half duplex, which is slow"
    run report
    check "report shows half duplex" has "half-duplex"
    echo 0 > "$SYS/class/net/eth0/carrier"
    link eth0 100
    run status
    lacks "cable link is only"
}

lacks_log() { ! grep -q "$1" "$LOG"; }
wifi_is() { [ "$(cat "$STATE/wifi" 2>/dev/null || echo disabled)" = "$1" ] || { echo "    Wi-Fi is $(cat "$STATE/wifi" 2>/dev/null || echo disabled), wanted $1"; return 1; }; }

test_wifi_fallback() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    run install -y --wifi-fallback --wait 4
    check "setting saved" grep -q '^WIFI_FALLBACK="1"' "$CONF"
    check "plan mentions Wi-Fi" has "turn Wi-Fi on"
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    check "no message on screen when it works" sh -c "! grep -q createToast '$STATE/luna.log'"
    check "watching" wait_log "Turning Wi-Fi on if eth0 has no cable link"
    sleep 2
    check "Wi-Fi left alone while the cable works" wifi_is disabled
    echo 0 > "$SYS/class/net/eth0/carrier"
    check "Wi-Fi turned on" wait_log "turning Wi-Fi on"
    check "Wi-Fi is on" wifi_is enabled
    check "marker kept" test -f "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.wifi"
    run status --json
    check "json shows it" json_ok "$OUT" "d['hook']['wifiFallback'] is True and d['hook']['wifiFallbackOn'] is True"
    run status
    check "status note" has "The Wi-Fi fallback turned Wi-Fi on"
    check "status hook line" has "Wi-Fi as a backup"
    echo 1 > "$SYS/class/net/eth0/carrier"
    check "Wi-Fi turned off again" wait_log "turning Wi-Fi off again"
    check "Wi-Fi is off" wifi_is disabled
    check "marker gone" test ! -f "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.wifi"
    # A second outage works too
    echo 0 > "$SYS/class/net/eth0/carrier"
    sleep 6
    check "second outage" test "$(grep -c 'turning Wi-Fi on' "$LOG")" = 2
    stop_bg
}

test_wifi_fallback_leaves_wifi_alone() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "00:e0:4c:68:00:01"
    echo enabled > "$STATE/wifi"
    run install -y --wifi-fallback --wait 4
    run_hook
    check "boot swaps" wait_log "Done: the USB adapter is eth0"
    echo 0 > "$SYS/class/net/eth0/carrier"
    sleep 6
    check "no setstate when Wi-Fi is already on" sh -c "! grep -q setstate '$STATE/luna.log'"
    check "nothing logged" lacks_log "turning Wi-Fi"
    stop_bg
    # Without the option, nothing happens at all
    echo disabled > "$STATE/wifi"
    rm -f "$STATE/luna.log" "$LOG"
    run install -y --no-wifi-fallback --watch
    check "setting off" grep -q '^WIFI_FALLBACK="0"' "$CONF"
    run_hook
    check "boot runs" wait_log "Watching for the adapter"
    sleep 5
    check "Wi-Fi untouched" sh -c "! grep -q 'wifi' '$STATE/luna.log' 2>/dev/null"
    stop_bg
}

test_wifi_fallback_settings() {
    add_builtin
    run install -y --wifi-fallback
    run install -y --watch
    check "kept by a later install" grep -q '^WIFI_FALLBACK="1"' "$CONF"
    echo on > "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.wifi"
    run uninstall -y
    check "uninstall warns" has "turned Wi-Fi on, and it stays on"
    check "marker removed" test ! -f "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.wifi"
    run --help
    check "help lists it" has "--wifi-fallback"
    run install -y
    sed -i 's/^WIFI_FALLBACK=.*/WIFI_FALLBACK="yes"/' "$CONF"
    run_hook
    check "bad value refused" wait_log "invalid settings"
}

# wait_for_file FILE TEXT: wait up to 15s for TEXT to show up in FILE
wait_for_file() {
    local i=0
    while [ "$i" -lt 15 ]; do
        grep -q "$2" "$1" 2>/dev/null && return 0
        sleep 1
        i=$((i + 1))
    done
    echo "    $1 never got: $2"
    return 1
}

# /etc/hosts as the Homebrew Channel's own block leaves it
hbc_hosts() {
    printf '%s\n' '127.0.0.1 localhost' '# This file is dynamically regenerated on boot by webosbrew startup script' \
        '127.0.0.1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com' '::1 snu.lge.com su-dev.lge.com su.lge.com su-ssl.lge.com' > "$SB/hosts"
}

# --block-updates adds to the Homebrew Channel's block, and undoes only its own
test_block_updates() {
    add_builtin
    hbc_hosts
    mkdir -p "$ROOT/mnt/lg/cmn_data/swupdate"
    echo x > "$ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    run install -y --block-updates
    check "exit 0" rc_is 0
    check "saved" grep -q '^BLOCK_UPDATES="1"' "$CONF"
    check "update check off" grep -qx false "$STATE/updcheck"
    check "remembers it was on" grep -qx true "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates"
    check "adds nsu.lge.com" grep -q "nsu.lge.com" "$SB/hosts"
    check "adds snu-dev.lge.com" grep -q "snu-dev.lge.com" "$SB/hosts"
    check "doesn't repeat the HBC ones" sh -c "! grep 'lg-usb-2-eth0' '$SB/hosts' | grep -q ' snu.lge.com '"
    check "firewall rule" grep -q "156.147.69.32" "$STATE/iptables"
    check "cached update info gone" test ! -e "$ROOT/mnt/lg/cmn_data/swupdate/Image_Update_Info.xml"
    run install -y --block-updates
    check "one firewall rule" test "$(grep -c 156.147.69.32 "$STATE/iptables")" = 1
    check "hosts lines added once" test "$(grep -c 'nsu.lge.com' "$SB/hosts")" = 2
    run status --json
    check "json says on" has '"blockUpdates":true'
    check "json: nothing missing" has '"missingHosts":""'
    check "json: HBC block seen" has '"hbcBlock":false'
    run status
    check "status names it" has "blocks firmware updates"
    run install -y --no-block-updates
    check "update check back on" grep -qx true "$STATE/updcheck"
    check "our hosts lines gone" sh -c "! grep -q 'lg-usb-2-eth0' '$SB/hosts'"
    check "HBC's lines kept" grep -q '^127.0.0.1 snu.lge.com su-dev.lge.com' "$SB/hosts"
    check "firewall rule gone" sh -c "! grep -q 156.147.69.32 '$STATE/iptables'"
    check "mark gone" test ! -e "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates"
}

# With the Homebrew Channel's block off, --block-updates covers its servers too
test_block_updates_without_hbc() {
    add_builtin
    printf '%s\n' '127.0.0.1 localhost' '127.0.1.1 LGwebOSTV' > "$SB/hosts"
    cp "$SB/hosts" "$SB/hosts.orig"
    run install -y --block-updates
    check "says so" has "Block system updates is off"
    local h
    for h in snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com nsu.lge.com ngfts.lge.com; do
        check "blocks $h" grep -q "[[:space:]]$h " "$SB/hosts"
    done
    run status
    check "no warning" lacks "aren't blocked"
    run install -y --no-block-updates
    check "back as it was" cmp -s "$SB/hosts" "$SB/hosts.orig"
    run status
    check "warns when nothing blocks updates" has "Firmware updates aren't blocked"
    mkdir -p "$ROOT/var/luna/preferences"
    touch "$ROOT/var/luna/preferences/webosbrew_block_updates"
    run status
    check "points out what the HBC block misses" has "misses others"
}

# If the update check was already off, turning the option off leaves it off;
# uninstall undoes the rest; the boot hook blocks again after a reboot
test_block_updates_undo() {
    add_builtin
    hbc_hosts
    echo false > "$STATE/updcheck"
    run install -y --block-updates
    check "remembers it was off" grep -qx false "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.updates"
    run install -y --no-block-updates
    check "stays off" grep -qx false "$STATE/updcheck"
    echo true > "$STATE/updcheck"
    run install -y --block-updates
    : > "$STATE/iptables"
    hbc_hosts
    run_hook
    check "boot blocks again" wait_for_file "$STATE/iptables" 156.147.69.32
    check "boot adds hosts" grep -q "nsu.lge.com" "$SB/hosts"
    run uninstall -y
    check "uninstall says so" has "Undid --block-updates"
    check "update check back on" grep -qx true "$STATE/updcheck"
    check "hosts clean" sh -c "! grep -q 'lg-usb-2-eth0' '$SB/hosts'"
    check "firewall clean" sh -c "! grep -q 156.147.69.32 '$STATE/iptables'"
    run --help
    check "help lists it" has "--block-updates"
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

# What the TV app's Upgrade from v1 walk-through relies on: status --json
# reports the v1 hook, and install -y replaces it (a running one, or one
# "disabled" inside init.d) with a link, without touching the network
test_upgrade_v1_app() {
    add_builtin eth2
    add_usb eth0 1-1 r8152 1 "00:e0:4c:68:00:01"
    printf '#!/bin/sh\nip link set eth0 down\nip link set eth0 name eth2\n' > "$HOOK"
    chmod 755 "$HOOK"
    run status --json
    check "json says legacy" json_ok "$OUT" "d['hook']['state'] == 'legacy' and any('install' in i for i in d['issues'])"
    run install -y
    check "replaced by a link" test -L "$HOOK"
    run status --json
    check "json says enabled" json_ok "$OUT" "d['hook']['state'] == 'enabled' and d['hook']['link'] != '' and d['adapterIsEth0'] and not any('v1' in i for i in d['issues'])"
    check "adapter untouched" is eth0 usb:1-1
    rm -f "$HOOK" "$CONF"
    printf '#!/bin/sh\nip link set eth0 down\n' > "$HOOK.disabled"
    run status --json
    check "json says legacy-disabled" json_ok "$OUT" "d['hook']['state'] == 'legacy-disabled'"
    run install -y
    check "old disabled file gone" test ! -e "$HOOK.disabled"
    check "new hook is a link" test -L "$HOOK"
}

# After standby, webOS had the network up on cdc_ncm.  After the move to
# the faster driver it never reconnected (seen on a C2).  The hook takes the
# link down and up, and if that doesn't help, gives the adapter back.
standby_with_address() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot
    run install -y --module "$SB/r8152_oot.ko"
    run_hook
    check "boot swaps" wait_log "Keeping the adapter on r8152_oot"
    remove_usb 1-1
    add_usb eth0 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    echo 9 > "$SYS/devices/usb1/1-1/devnum"
    echo "2: eth0 inet 192.168.1.42/24" > "$STATE/addr"
}

test_standby_reconnects() {
    standby_with_address
    check "moves it" wait_log "Now on r8152_oot" 15
    sleep 5
    lacks_log "Taking the link down"
    check "on the new driver" drv eth0 r8152_oot
    stop_bg
}

test_standby_link_bounce() {
    touch "$STATE/no_dhcp_after_move" "$STATE/dhcp_on_up"
    standby_with_address
    check "bounces the link" wait_log "Taking the link down and up" 20
    check "reconnects" wait_log "eth0 is connected again." 10
    check "stays on the new driver" drv eth0 r8152_oot
    stop_bg
}

test_standby_gives_back() {
    touch "$STATE/no_dhcp_after_move" "$STATE/dhcp_on_generic"
    standby_with_address
    check "gives it back" wait_log "Giving the adapter back to cdc_ncm" 25
    check "reconnects on cdc_ncm" wait_log "eth0 is connected again, on cdc_ncm." 15
    check "on cdc_ncm" drv eth0 cdc_ncm
    check "still eth0" is eth0 usb:1-1
    sleep 6
    check "not moved again" test "$(grep -c 'generic driver again' "$LOG")" = 1
    stop_bg
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
    check "lists the adapter's driver" has "Drivers loaded: r8152"
    check "no modules.builtin: unknown" has "Built in: unknown"
    local k
    k=$ROOT/lib/modules/$(uname -r)
    mkdir -p "$k"
    printf '%s\n' kernel/drivers/net/usb/r8152.ko kernel/drivers/net/usb/cdc_ncm.ko kernel/drivers/usb/core/usbcore.ko > "$k/modules.builtin"
    FAKE_SOC=o22 run report
    check "names the chip" has "Chip:    o22"
    check "lists built-in drivers" has "Built in: r8152 cdc_ncm"
}

# The TV app shows what's new after an update: status --json says which
# version the last in-app update installed
test_status_updated_to() {
    add_builtin
    run status --json
    check "no update yet" has '"updatedTo":""'
    printf '%s\n' '=== update to 2.4.2 ===' 'Updated the app to 2.4.2.' '=== update to 2.4.3 ===' 'Updated the app to 2.4.3.' > "$LOG"
    run status --json
    check "the last update" has '"updatedTo":"2.4.3"'
    echo 'The app update to 2.4.4 did not finish.  The current version stays installed.' >> "$LOG"
    run status --json
    check "a failed update doesn't count" has '"updatedTo":"2.4.3"'
}

# A driver built into the kernel has no /sys/module folder, like ASIX on a G4
test_report_builtin_driver() {
    add_builtin
    add_usb eth1 1-1 ax88179_178a 1 "c8:a3:62:00:00:01" 0b95 1790 480
    run report
    check "exit 0" rc_is 0
    check "lists the built-in driver" has "Drivers loaded: ax88179_178a"
}

# realtek_adapter: an RTL8153 that a 4.4 kernel left in its standard mode
# (USB configuration 2), on cdc_ncm, with r8152 built in, like on a C9
realtek_adapter() {
    add_builtin
    mkdir -p "$SYS/bus/usb/drivers/r8152"
    add_usb eth1 1-1 cdc_ncm 1 "00:e0:4c:68:00:01" 0bda 8153 480
    echo 2 > "$SYS/devices/usb1/1-1/bConfigurationValue"
    echo 2 > "$SYS/devices/usb1/1-1/bNumConfigurations"
}

test_realtek_mode_off() {
    realtek_adapter
    LGU2E_REALTEK_MODE=0 run apply -y
    check "adapter is eth0" is eth0 usb:1-1
    check "configuration untouched" sh -c "! grep -q bConfigurationValue '$STATE/syswrite.log' 2>/dev/null"
    check "still on cdc_ncm" drv eth0 cdc_ncm
    LGU2E_REALTEK_MODE=0 run status
    check "status explains" has "in its standard USB mode"
    check "says how to turn it on" has "install --realtek-mode"
}

test_realtek_mode_on() {
    realtek_adapter
    run apply -y
    check "switched" has "switching it from USB configuration 2 to its Realtek mode"
    check "now on r8152" has "Now on r8152."
    check "adapter is eth0" is eth0 usb:1-1
    check "on r8152" drv eth0 r8152
}

test_realtek_mode_fallback() {
    realtek_adapter
    touch "$STATE/cfg_fail"
    LGU2E_REALTEK_MODE=1 run apply -y
    check "puts it back" has "Putting it back in USB configuration 2"
    check "adapter is eth0" is eth0 usb:1-1
    check "back on cdc_ncm" drv eth0 cdc_ncm
    check "configuration 2" sh -c "[ \"\$(cat '$SYS/devices/usb1/1-1/bConfigurationValue')\" = 2 ]"
    run status
    check "status says it was tried" has "Realtek mode was tried"
    run report
    check "report shows the result" has "Realtek mode: failed 0bda:8153"
}

# The setting is saved, the boot hook uses it, and --no-realtek-mode leaves
# the adapter alone at boot
test_realtek_mode_setting() {
    realtek_adapter
    run install -y
    check "on by default" has "its Realtek mode, so the kernel's own r8152 takes it"
    check "saved on" grep -q '^REALTEK_MODE="1"' "$CONF"
    run_hook
    check "boot switches it" wait_log "Now on r8152."
    check "on r8152 after boot" drv eth0 r8152
    run status --json
    check "json shows it on" has '"realtekMode":true'
    check "json shows the result" has '"result":"ok"'
    run install -y --no-realtek-mode
    check "saved off" grep -q '^REALTEK_MODE="0"' "$CONF"
    run report
    check "report says off" has "no-realtek-mode"
}

# A Realtek driver built into the kernel, with no adapter on it (like r8152 on
# a 2019 C9, whose RTL8153 lands on cdc_ncm): lsmod doesn't show it, status must
test_status_builtin_driver() {
    add_builtin
    mkdir -p "$SYS/bus/usb/drivers/r8152"
    add_usb eth1 1-1 cdc_ncm 1 "00:e0:4c:68:00:01"
    run status
    check "registered driver counts as built in" has "r8152(built in)"
    local k
    k=$ROOT/lib/modules/$(uname -r)
    mkdir -p "$k"
    printf '%s\n' kernel/drivers/net/usb/cdc_ncm.ko > "$k/modules.builtin"
    run status
    check "modules.builtin counts too" has "cdc_ncm(built in)"
    run report
    check "report lists it" has "Drivers loaded: r8152"
}

t help test_help
t status_clean test_status_clean
t apply_swaps test_apply_swaps
t apply_virtual_builtin test_apply_virtual_builtin
t apply_virtual_bridge test_apply_virtual_bridge_left_alone
t app_tv_info test_app_tv_info
t wake_path test_wake_path
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
t watch_hung_adapter test_watch_hung_adapter
t link_speed test_link_speed
t wifi_fallback test_wifi_fallback
t wifi_fallback_leaves_wifi_alone test_wifi_fallback_leaves_wifi_alone
t wifi_fallback_settings test_wifi_fallback_settings
t block_updates test_block_updates
t block_updates_undo test_block_updates_undo
t block_updates_without_hbc test_block_updates_without_hbc
t disable_enable test_disable_enable
t upgrade_v1 test_upgrade_v1
t v1_disabled_in_initd test_v1_disabled_in_initd
t upgrade_v1_app test_upgrade_v1_app
t standby_reconnects test_standby_reconnects
t standby_link_bounce test_standby_link_bounce
t standby_gives_back test_standby_gives_back
t uninstall_now test_uninstall_now
t module_rejects_bad_path test_module_rejects_bad_path
t module_missing test_module_missing
t module_loaded_at_boot test_module_loaded_at_boot
t unclaimed_adapter test_unclaimed_adapter
t usb2_note test_usb2_note

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

# The TV app's language reaches the boot hook's messages on the TV screen
test_toast_in_app_language() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot 5.4.268-old
    APP_LANG=ru FAKE_KERNEL=5.4.268-old run install -y --module "$SB/r8152_oot.ko"
    check "installed" rc_is 0
    check "language saved" grep -q '^UI_LANG="ru"$' "$CONF"
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "message in Russian" grep -q "createToast.*быстрый драйвер собран для старого ядра" "$STATE/luna.log"
    APP_LANG=en run status --json
    check "app back in English: saved" grep -q '^UI_LANG="en"$' "$CONF"
    run status
    check "a run over SSH leaves it" grep -q '^UI_LANG="en"$' "$CONF"
    APP_LANG=xx run status --json
    check "an unknown language is ignored" grep -q '^UI_LANG="en"$' "$CONF"
    APP_LANG=es run status --json
    check "Spanish saved" grep -q '^UI_LANG="es"$' "$CONF"
}

test_toast_in_spanish() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot 5.4.268-old
    APP_LANG=es FAKE_KERNEL=5.4.268-old run install -y --module "$SB/r8152_oot.ko"
    check "installed" rc_is 0
    check "language saved" grep -q '^UI_LANG="es"$' "$CONF"
    run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "message in Spanish" grep -q "createToast.*hecho para el kernel anterior" "$STATE/luna.log"
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
    check "says so on screen" grep -q "createToast.*built for the old kernel" "$STATE/luna.log"
    check "never loaded" test ! -e "$STATE/insmod.log"
    check "stays on cdc_ncm" drv eth0 cdc_ncm
    run status
    check "status flags it" has "so a firmware update changed it"
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
    run status --json
    check "history kept, with the driver" json_ok "$OUT" "len(d['speedHistory']) == 1 and d['speedHistory'][0]['downMbps'] == 1600 and d['speedHistory'][0]['driver'] == 'r8152'"
    run speedtest
    check "earlier tests listed" has "Earlier tests"
    run status --json
    check "newest first, two kept" json_ok "$OUT" "len(d['speedHistory']) == 2 and d['speedHistory'][0]['at'] >= d['speedHistory'][1]['at']"
    check "kept across reboots" test -s "$ROOT/var/lib/webosbrew/lg-usb-2-eth0.speeds"
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
    # Versions compare by number, not as text: X.(Y+1).0 is newer, and
    # X.(Y-1).99 isn't (as text, "2.9.99" would beat "2.10.0")
    local ma mi
    ma=${v%%.*} mi=${v#*.}; mi=${mi%%.*}
    release "$ma.$((mi + 1)).0"
    run update --check --json
    check "the next minor version is newer" json_ok "$OUT" "d['newer'] is True and d['notes'].endswith('/tag/v$ma.$((mi + 1)).0')"
    if [ "$mi" -gt 0 ]; then
        release "$ma.$((mi - 1)).99"
        run update --check --json
        check "an older minor with a bigger patch isn't newer" json_ok "$OUT" "d['newer'] is False"
    fi
    release "$ma.$((mi + 1)).0"
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

# webOS 26's installer can't read /tmp: the IPK goes to the developer temp folder
test_update_app_devtemp() {
    local app="$ROOT/media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0"
    mkdir -p "$app/assets" "$ROOT/media/developer/temp"
    cp "$SCRIPT" "$app/assets/lg-usb-2-eth0.sh"
    printf '{\n  "id": "org.ohmybahgosh.lgusb2eth0",\n  "version": "2.3.0"\n}\n' > "$app/appinfo.json"
    mkdir -p "$STATE/rel"
    echo "fake ipk" > "$STATE/rel/app.ipk"
    release 2.4.0
    echo 2.4.0 > "$STATE/appver"
    local SCRIPT="$app/assets/lg-usb-2-eth0.sh"
    run update -y
    check "exit 0" rc_is 0
    local i=0
    while ! grep -q "Updated the app to 2.4.0" "$LOG" 2>/dev/null && [ $i -lt 30 ]; do sleep 0.2; i=$((i + 1)); done
    check "installer reads it from the developer temp folder" grep -q "media/developer/temp/lg-usb-2-eth0-update.ipk" "$STATE/luna.log"
    check "cleaned up the download" sh -c "! ls '$ROOT'/media/developer/temp/lg-usb-2-eth0-update.ipk* 2>/dev/null | grep -q ."
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

# webOS 5 (2020 UN7300): no ASIX driver in the kernel, OCT0PUSCRIME's build
test_driver_offer_webos5_asix() {
    add_builtin
    local k=4.4.84-612.jcl4tv.40
    add_unclaimed 1-1 0b95 1790
    FAKE_KERNEL=$k run status --json
    check "unclaimed AX88179: available" offer_is available
    check "names who built it" has '"driverPage":"https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver"'
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8153
    FAKE_KERNEL=$k run status --json
    check "a Realtek adapter: none" offer_is none
    remove_usb 1-1
    add_unclaimed 1-1 0b95 1790
    printf 'not the module' > "$SB/ax88179_178a.ko"
    FAKE_KERNEL=$k run get-driver -y --file "$SB/ax88179_178a.ko"
    check "names the ASIX build" has "OCT0PUSCRIME/lg-webos-ax88179-driver"
    check "says it fits the adapter" has "It supports your adapter (0b95:1790)"
    check "still refuses a wrong file" has "Checksum mismatch"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/ax88179_178a.ko"
    rm -f "$STATE/curl.log"
    FAKE_KERNEL=$k run get-driver -y
    check "pinned download" grep -q "raw.githubusercontent.com/OCT0PUSCRIME/lg-webos-ax88179-driver/734b54c" "$STATE/curl.log"
}

# The author's repository is gone: get-driver falls back to the mirror, and
# the mirror's file still has to match the pinned SHA-256
test_get_driver_mirror() {
    add_builtin
    local k=5.4.268-329.ptl4tv.5
    printf 'DonZoomik/webos-r8152' > "$STATE/curl_404"
    FAKE_KERNEL=$k run get-driver -y
    check "tried the author first" grep -q "raw.githubusercontent.com/DonZoomik/webos-r8152/1ea8e98" "$STATE/curl.log"
    check "then the pinned mirror" grep -q "raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e7.*/drivers/$k/r8152_oot.ko" "$STATE/curl.log"
    check "says so" has "Trying the mirror"
    check "mirror file checked too" has "Checksum mismatch"
    check "nothing kept" test ! -e "$ROOT/home/root/lg-usb-2-eth0/drivers/r8152_oot.ko"
}

# 2025 B5: dd3git's ASIX build, whose vermagic says only 5.4.268
test_driver_offer_2025_asix() {
    add_builtin
    local k=5.4.268-294.24.papikonda.2
    add_unclaimed 1-1 0b95 1790
    FAKE_KERNEL=$k run status --json
    check "unclaimed AX88179: available" offer_is available
    check "names who built it" has '"driverPage":"https://github.com/dd3git/lg-webos-ax88179-driver"'
    FAKE_KERNEL=$k run get-driver -y
    check "pinned download" grep -q "raw.githubusercontent.com/dd3git/lg-webos-ax88179-driver/3a871c9" "$STATE/curl.log"
    check "still checksummed" has "Checksum mismatch"
}

# A module whose vermagic has only the base version is refused, unless it's
# a known driver for this exact kernel (matched by SHA-256)
test_base_vermagic_needs_known_sha() {
    add_builtin
    local k=5.4.268-294.24.papikonda.2
    fake_ko "$SB/ax.ko" ax88179_178a 5.4.268 0b95:1790
    FAKE_KERNEL=$k run install -y --module "$SB/ax.ko"
    check "unknown file refused" rc_is 1
    check "says why" has "built for kernel 5.4.268"
    local sum
    sum=$(sha256sum "$SB/ax.ko" | awk '{print $1}')
    LGU2E_TEST_DRIVER="https://example.test/ax.ko $sum ax.ko https://example.test 0b95:1790" FAKE_KERNEL=$k run install -y --module "$SB/ax.ko"
    check "known file accepted" rc_is 0
    LGU2E_TEST_DRIVER="https://example.test/ax.ko $sum ax.ko https://example.test 0b95:1790" FAKE_KERNEL=$k run status --json
    check "offer is active, not wrong-kernel" offer_is active
}

# K5Lp: throwaway96's per-chip builds, picked by the adapter plugged in
test_driver_offer_k5lp() {
    add_builtin
    add_unclaimed 1-1 0bda 8153
    FAKE_SOC=k5lp FAKE_KERNEL=4.4.84 run status --json
    check "RTL8153 on K5Lp: available" offer_is available
    check "the r8152 build" has '/drivers/r8152.ko"'
    check "names who built it" has '"driverPage":"https://github.com/throwaway96/webos-kernel-drivers"'
    FAKE_SOC=o18 FAKE_KERNEL=4.4.84 run status --json
    check "another chip: none" offer_is none
    remove_usb 1-1
    add_unclaimed 1-1 0b95 1790
    FAKE_SOC=K5LP FAKE_KERNEL=4.4.84 run status --json
    check "AX88179 on K5Lp: the ASIX build" has '/drivers/ax88179_178a.ko"'
    FAKE_SOC=k5lp FAKE_KERNEL=4.4.84-612.jcl4tv.40 run status --json
    check "an exact-kernel build wins" has '"driverPage":"https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver"'
    FAKE_KERNEL=4.4.84 run status --json
    check "no chip known: none" offer_is none
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

# test-driver: a new driver built for this kernel, tried until the next restart
DT=""
drvtest_file() { DT=$ROOT/var/lib/webosbrew/lg-usb-2-eth0.drvtest; }
dt_is() { grep -qx "$1" "$DT" || { echo "    $DT lacks $1:"; sed 's/^/      /' "$DT" 2>/dev/null; return 1; }; }

# An adapter on cdc_ncm, and a driver to test for a made-up kernel
# (5.4.268-999), so promoting real drivers never changes these tests
drvtest_setup() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8153 5000
    fake_ko "$STATE/download" r8152_oot 5.4.268-999 0bda:8153 0bda:8156
    XDRV="https://example.test/r8152_oot.ko $(sha256sum "$STATE/download" | awk '{print $1}') r8152_oot.ko 5.4.268-999 0bda:8153,0bda:8156"
    drvtest_file
}

# webOS hasn't given the adapter an address within the wait (an older webOS
# can be slow, issue #17): the link goes down and up, webOS reconnects, and
# the test reports it works
test_test_driver_link_bounce() {
    drvtest_setup
    touch "$STATE/dhcp_on_up"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "exit 0" rc_is 0
    check "took the link down and up" has "Taking the link down and up so webOS sees it"
    check "bounced the adapter, not the built-in port" grep -q "ip link set dev eth1 up" "$STATE/ip.log"
    check "result works" dt_is "result=works"
}

test_test_driver_works() {
    drvtest_setup
    # webOS gives the adapter an address once it's on the new driver
    echo "2: eth1 inet 192.168.1.42/24" > "$STATE/addr"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run status --json
    check "offered" has '"driverTest":{"available":true,"adapterOk":true,"folder":"5.4.268-999","state":"","result":""}'
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "exit 0" rc_is 0
    check "verified" has "Downloaded and verified"
    check "loaded from RAM, not kept" grep -q "insmod $ROOT/tmp/lg-usb-2-eth0-test-r8152_oot.ko" "$STATE/insmod.log"
    check "moved the adapter" has "cdc_ncm -> r8152_oot"
    check "adapter on the new driver" drv eth1 r8152_oot
    check "result works" dt_is "result=works"
    check "says so" has "it works"
    check "pinged through the adapter" grep -q -- "-I eth1" "$STATE/ping.log"
    check "report has the kernel log" has "registered new interface driver r8152_oot"
    check "report hides the MAC" lacks "6c:1f:f7:00:00:01"
    check "and links the form" has "template=driver-test.yml"
    check "no boot hook set up" test ! -e "$HOOK"
    run report
    check "report line" has "Driver test: works (experimental/5.4.268-999)"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run status --json
    check "status has the result" has '"state":"done","result":"works"'
}

# Realtek mode had already moved the adapter to the kernel's own r8152 (a
# 2024 G4 on 5.4.268-320, issue #5): the test moves it from there
test_test_driver_from_r8152() {
    add_builtin
    add_usb eth1 1-1 r8152 1 "6c:1f:f7:00:00:01" 0bda 8153 480
    fake_ko "$STATE/download" r8152_oot 5.4.268-999 0bda:8153 0bda:8156
    XDRV="https://example.test/r8152_oot.ko $(sha256sum "$STATE/download" | awk '{print $1}') r8152_oot.ko 5.4.268-999 0bda:8153,0bda:8156"
    drvtest_file
    echo "2: eth1 inet 192.168.1.42/24" > "$STATE/addr"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "moved from r8152" has "r8152 -> r8152_oot"
    check "adapter on the new driver" drv eth1 r8152_oot
    check "result works" dt_is "result=works"
    check "report says where it was" has "Before:   r8152"
}

# The TV app starts the test and follows it through status --json
test_test_driver_no_wait() {
    drvtest_setup
    echo "2: eth1 inet 192.168.1.42/24" > "$STATE/addr"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y --no-wait
    check "exit 0" rc_is 0
    check "no report printed" lacks "template=driver-test.yml"
    local i=0
    while [ "$i" -lt 20 ] && ! grep -qx "state=done" "$DT" 2>/dev/null; do sleep 1; i=$((i + 1)); done
    check "finishes in the background" dt_is "result=works"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver --last
    check "--last shows it" has "Result:   works"
}

test_test_driver_eth0_kept() {
    drvtest_setup
    run apply -y
    check "adapter is eth0" is eth0 usb:1-1
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "still eth0 after the move" is eth0 usb:1-1
    check "on the new driver" drv eth0 r8152_oot
    check "no address: no internet" dt_is "result=no-internet"
}

test_test_driver_no_load() {
    drvtest_setup
    touch "$STATE/insmod_fail"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "result no-load" dt_is "result=no-load"
    check "kernel's message kept" has "invalid module format"
    check "adapter untouched" drv eth1 cdc_ncm
}

test_test_driver_crashed() {
    drvtest_setup
    printf 'state=running\nboot=boot1\nkernel=5.4.268-999\nchip=o22\nadapter=0bda:8153 (Realtek RTL8153)\nfolder=5.4.268-999\nsha=abc\n' > "$DT"
    FAKE_KERNEL=5.4.268-999 run test-driver -y
    check "same boot: still running" has "still running"
    FAKE_BOOT_ID=boot2 FAKE_KERNEL=5.4.268-999 run test-driver --last
    check "a restart in between: crashed" dt_is "result=crashed"
    check "says so" has "froze or restarted"
    check "report says crashed" has "Result:   crashed"
    LGU2E_TEST_EXPERIMENTAL=$XDRV FAKE_BOOT_ID=boot2 FAKE_KERNEL=5.4.268-999 run test-driver
    check "asks before trying again" has "Try it once more?"
    check "and didn't" test ! -e "$STATE/insmod.log"
}

test_test_driver_checks() {
    add_builtin
    drvtest_file
    FAKE_KERNEL=9.9.9-other run test-driver -y
    check "nothing for this kernel" has "No new driver to test for kernel 9.9.9-other"
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run test-driver -y
    check "points to the tested one" has "It does have a tested one"
    # The K24 build only on K24, and only with a supported adapter
    FAKE_SOC=k9xyz FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "other chip: nothing" has "No new driver to test"
    FAKE_SOC=k8hpp FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "K8Hpp has its own build" has "Plug in a USB adapter with a chip the new driver is for"
    FAKE_SOC=k24 FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "no adapter: refused" has "Plug in a USB adapter with a chip the new driver is for"
    check "nothing downloaded" test ! -e "$STATE/curl.log"
    add_unclaimed 1-1 0bda 8153
    FAKE_SOC=k24 FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "pinned experimental download" grep -q "lg-webos-usb-drivers/e32c059.*/experimental/5.4.268-294.24.papikonda.2-k24/r8152_oot.ko" "$STATE/curl.log"
    check "checksummed" has "Checksum mismatch"
    check "no test started" test ! -e "$DT"
    check "nothing loaded" test ! -e "$STATE/insmod.log"
    # An ASIX adapter there has a tested driver (dd3git's), so no test
    remove_usb 1-1
    add_unclaimed 1-1 0b95 1790
    FAKE_SOC=k24 FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "ASIX: use the tested one" has "has a tested driver for your adapter"
    # A build reported working moves to TESTED_DRIVERS: get-driver offers it,
    # and test-driver doesn't test it again
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8153
    : > "$STATE/curl.log"
    LGU2E_TEST_TESTED="5.4.268-294.24.papikonda.2 k24 r8152_oot.ko 0000000000000000000000000000000000000000000000000000000000000000" \
        FAKE_SOC=k24 FAKE_KERNEL=5.4.268-294.24.papikonda.2 run test-driver -y
    check "tested: no new test" has "has a tested driver for your adapter"
    LGU2E_TEST_TESTED="5.4.268-294.24.papikonda.2 k24 r8152_oot.ko 0000000000000000000000000000000000000000000000000000000000000000" \
        FAKE_SOC=k24 FAKE_KERNEL=5.4.268-294.24.papikonda.2 run get-driver -y
    check "tested: get-driver downloads it" grep -q "e32c059.*/experimental/5.4.268-294.24.papikonda.2-k24/r8152_oot.ko" "$STATE/curl.log"
}

# 2020 K6Lp TVs: a Realtek and an ASIX build per kernel, picked by adapter
test_test_driver_k6lp() {
    add_builtin
    drvtest_file
    FAKE_SOC=k6hp FAKE_KERNEL=4.4.84-612.40.jimna.1 run test-driver -y
    check "K6Hp: its own builds" has "ASIX AX88179, or Realtek RTL8152, RTL8153 or RTL8156"
    check "K6Hp: its own builds: and the new chips" has "or Davicom DM9601, or Microchip LAN7800 or LAN7850."
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run test-driver -y
    check "no adapter: names both" has "ASIX AX88179, or Realtek RTL8152, RTL8153 or RTL8156"
    check "no adapter: names both: and the new chips" has "or Davicom DM9601, or Microchip LAN7800 or LAN7850."
    add_unclaimed 1-1 0b95 1790
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run status --json
    check "offered with the adapter" has '"driverTest":{"available":true,"adapterOk":true,"folder":"4.4.84-612.40.jimna.1-k6lp"'
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run test-driver -y
    check "ASIX: the ASIX build" grep -q "e32c059.*/experimental/4.4.84-612.40.jimna.1-k6lp/ax88179_178a.ko" "$STATE/curl.log"
    check "checksummed" has "Checksum mismatch"
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8153
    : > "$STATE/curl.log"
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.21.6.jardine.2 run test-driver -y
    check "Realtek: the r8152 build" grep -q "e32c059.*/experimental/4.4.84-612.21.6.jardine.2-k6lp/r8152.ko" "$STATE/curl.log"
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8156
    : > "$STATE/curl.log"
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run test-driver -y
    check "RTL8156: Realtek's newer driver" grep -q "e32c059.*/experimental/4.4.84-612.40.jimna.1-k6lp/r8152_oot.ko" "$STATE/curl.log"
    # The UN7300's kernel: its r8152 for an RTL8153 was reported working
    # (issue #6), so it's offered as a known driver, not a test
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8153
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.jcl4tv.40 run status --json
    check "jcl4tv.40, RTL8153: r8152 is a known driver" has '"driverPage":"https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.jcl4tv.40-k6lp"'
    # An RTL8156 still gets Realtek's newer driver to test
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8156
    : > "$STATE/curl.log"
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.jcl4tv.40 run test-driver -y
    check "jcl4tv.40, RTL8156: r8152_oot" grep -q "e32c059.*/experimental/4.4.84-612.jcl4tv.40-k6lp/r8152_oot.ko" "$STATE/curl.log"
    # A TV whose nyx-cmd doesn't name the chip when the app runs the script
    # (issue #6): the firmware's machine name does
    mkdir -p "$ROOT/etc/prefs/properties" && echo k6lp > "$ROOT/etc/prefs/properties/machineName"
    : > "$STATE/curl.log"
    FAKE_SOC='' FAKE_KERNEL=4.4.84-612.jcl4tv.40 run status --json
    check "no nyx chip: offered from machineName" has '"driverTest":{"available":true'
    FAKE_SOC='' FAKE_KERNEL=4.4.84-612.jcl4tv.40 run test-driver -y
    check "no nyx chip: jcl4tv.40 r8152_oot" grep -q "e32c059.*/experimental/4.4.84-612.jcl4tv.40-k6lp/r8152_oot.ko" "$STATE/curl.log"
    rm -f "$ROOT/etc/prefs/properties/machineName"
    remove_usb 1-1
    add_unclaimed 1-1 0bda 8156
    # webOS 22 K8 TVs: the Realtek build of their own chip
    : > "$STATE/curl.log"
    FAKE_SOC=k8lp FAKE_KERNEL=5.4.96-115.30.mole.2 run test-driver -y
    check "mole.2 K8Lp: r8152_oot" grep -q "e32c059.*/experimental/5.4.96-115.30.mole.2-k8lp/r8152_oot.ko" "$STATE/curl.log"
    # webOS 24 K24 TVs on a 5.4.268 223 kernel
    : > "$STATE/curl.log"
    FAKE_SOC=k24 FAKE_KERNEL=5.4.268-223.29.okapi.5 run test-driver -y
    check "okapi.5 K24: r8152_oot" grep -q "e32c059.*/experimental/5.4.268-223.29.okapi.5-k24/r8152_oot.ko" "$STATE/curl.log"
    # paparoa.pine.2 has a tested r8152, but not for an RTL8156: the build to test is offered
    : > "$STATE/curl.log"
    FAKE_SOC=k8hp FAKE_KERNEL=5.4.268-294.17.paparoa.pine.2 run test-driver -y
    check "paparoa K8Hp, RTL8156: r8152_oot" grep -q "e32c059.*/experimental/5.4.268-294.17.paparoa.pine.2-k8hp/r8152_oot.ko" "$STATE/curl.log"
}

# An adapter no driver has: the new one takes it as it loads (no cdc_ncm
# to move it from), and the driver name comes from the module
test_test_driver_unclaimed() {
    add_builtin
    add_unclaimed 1-1 0b95 1790
    echo 6c:1f:f7:00:00:02 > "$STATE/mac_1-1"
    fake_ko "$STATE/download" ax88179_178a 4.4.84-612.40.jimna.1 0b95:1790
    drvtest_file
    echo "2: eth1 inet 192.168.1.43/24" > "$STATE/addr"
    LGU2E_TEST_EXPERIMENTAL="https://example.test/ax88179_178a.ko $(sha256sum "$STATE/download" | awk '{print $1}') ax88179_178a.ko 4.4.84-612.40.jimna.1-k6lp 0b95:1790" \
        FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run test-driver -y
    check "exit 0" rc_is 0
    check "names the driver" has "new driver to test for kernel 4.4.84-612.40.jimna.1: ax88179_178a"
    check "adapter on it" drv eth1 ax88179_178a
    check "result works" dt_is "result=works"
    check "report names the file" has "experimental/4.4.84-612.40.jimna.1-k6lp/ax88179_178a.ko"
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

json_is() {
    printf '%s' "$OUT" > "$SB/o.json"
    python3 -c "import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; assert v==sys.argv[3], v" "$SB/o.json" "$1" "$2" || { echo "    $1 is not $2"; return 1; }
}

# A firmware update moves the kernel on: the saved driver isn't loaded, and
# status says what to do (switch, test, or report)
test_driver_after_firmware_update() {
    add_builtin
    add_usb eth1 1-1 cdc_ncm 1 "6c:1f:f7:00:00:01" 0bda 8156 480
    fake_ko "$SB/r8152_oot.ko" r8152_oot 5.4.268-329.ptl4tv.2
    FAKE_KERNEL=5.4.268-329.ptl4tv.2 run install -y --module "$SB/r8152_oot.ko"
    check "installed" rc_is 0
    FAKE_KERNEL=5.4.268-329.ptl4tv.2 run status --json
    check "kernel saved at setup" json_is kernelAtSetup 5.4.268-329.ptl4tv.2
    check "still active" offer_is active
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "new kernel with a known driver: replace" offer_is replace
    FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status
    check "says the kernel changed" has "it was 5.4.268-329.ptl4tv.2 when you set it up"
    check "says how to switch" has "run 'get-driver', then 'install --module"
    FAKE_KERNEL=9.9.9 run status --json
    check "nothing known: wrong-kernel" offer_is wrong-kernel
    FAKE_KERNEL=9.9.9 run status
    check "asks for a report" has "No driver is known for this kernel yet"
    FAKE_KERNEL=9.9.9 run report
    check "report names the setup kernel" has "set up on kernel 5.4.268-329.ptl4tv.2"
}

dt_json() {
    printf '%s' "$OUT" > "$SB/o.json"
    python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['driverTest']; v='%s %s' % (str(d['available']).lower(), str(d['adapterOk']).lower()); assert v==sys.argv[2], v" "$SB/o.json" "$1" || { echo "    driverTest is not $1"; return 1; }
}

# The new chips' drivers: offered to test when their adapter is plugged in,
# with each kernel's own list of adapters (older kernels know fewer)
test_new_chip_drivers() {
    add_builtin
    add_unclaimed 1-1 0424 7800
    FAKE_SOC=k8lp FAKE_KERNEL=5.4.96-115.30.mole.2 run status --json
    check "LAN7800 on K8Lp: a driver to test" dt_json "true true"
    remove_usb 1-1
    add_unclaimed 1-2 07c9 0012
    FAKE_SOC=k8lp FAKE_KERNEL=5.4.96-115.30.mole.2 run status --json
    check "a newer LAN78xx id isn't in 5.4.96's driver" dt_json "true false"
    FAKE_SOC=k24n FAKE_KERNEL=5.4.268-294.24.papikonda.2 run status --json
    check "but is in 5.4.268's" dt_json "true true"
    remove_usb 1-2
    add_unclaimed 1-3 2eca c101
    FAKE_SOC=k6lp FAKE_KERNEL=4.4.84-612.40.jimna.1 run status --json
    check "no aqc111 for 4.4 kernels" dt_json "true false"
    FAKE_SOC=k6lp FAKE_KERNEL=5.4.96-115.30.mole.2 run status --json
    check "other chip's folder: nothing to test" dt_json "false false"
    FAKE_SOC=k8hp FAKE_KERNEL=5.4.96-115.30.mole.2 run status --json
    check "AQC111 on K8Hp" dt_json "true true"
    FAKE_SOC=k8hp FAKE_KERNEL=5.4.96-115.30.mole.2 run report
    check "report names the chip" has "no driver: 2eca:c101 (Aquantia AQC111/112)"
    remove_usb 1-3
    # A C2 (ptl4tv.5): its drivers to test are only for chips it lacks, so
    # an adapter that already works isn't asked to test anything
    FAKE_SOC=o22 FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "C2, no adapter: there's something to test" dt_json "true false"
    add_usb eth3 1-4 ax88179_178a 1 "00:0e:c6:00:00:02" 0b95 1790
    FAKE_SOC=o22 FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "C2, ASIX on its own driver: nothing to test" dt_json "false false"
    remove_usb 1-4
    add_unclaimed 1-5 0424 7850
    FAKE_SOC=o22 FAKE_KERNEL=5.4.268-329.ptl4tv.5 run status --json
    check "C2, LAN7850 with no driver: lan78xx to test" dt_json "true true"
    remove_usb 1-5
    # One kernel name, two chips: the 2020 NANO99 8K (O208K) has no Realtek
    # driver, the CX (O20) on the same kernel name has it built in
    add_unclaimed 1-6 0bda 8153
    FAKE_SOC=o208k FAKE_KERNEL=4.4.84-219.jcl4tvmr.6 run status --json
    check "NANO99 8K, RTL8153: a driver to test" dt_json "true true"
    check "from its chip's folder" has '"folder":"4.4.84-219.jcl4tvmr.6-o208k"'
    FAKE_SOC=o20 FAKE_KERNEL=4.4.84-219.jcl4tvmr.6 run status --json
    check "CX on the same kernel name: nothing to test" dt_json "false false"
    FAKE_SOC=e60n FAKE_KERNEL=4.4.84-229.kcl4tv.6 run status --json
    check "QNED99 (E60N): a driver to test" has '"folder":"4.4.84-229.kcl4tv.6-e60n"'
    # 2019 webOS 4.5: the UM7300 (K5LP) has usbnet; the LM63 (M3R) has nothing
    # throwaway96's r8152 already covers an RTL8153 there, so nothing to test
    FAKE_SOC=k5lp FAKE_KERNEL=4.4.84-p.649.grampians.k5lp.1 run status --json
    check "UM7300 (K5LP), RTL8153: throwaway96's driver, nothing to test" has '"driverOffer":"available"'
    remove_usb 1-6
    add_unclaimed 1-9 0bda 8156
    FAKE_SOC=k5lp FAKE_KERNEL=4.4.84-p.649.grampians.k5lp.1 run status --json
    check "UM7300 (K5LP), RTL8156: a driver to test" dt_json "true true"
    check "from its chip's folder" has '"folder":"4.4.84-p.649.grampians.k5lp.1-k5lp"'
    remove_usb 1-9
    add_unclaimed 1-7 2001 4a00
    FAKE_SOC=m3r FAKE_KERNEL=4.4.84-433 run status --json
    check "LM63 (M3R), ASIX AX88179: a driver to test" dt_json "true true"
    check "from its chip's folder" has '"folder":"4.4.84-433-m3r"'
    remove_usb 1-7
    add_unclaimed 1-8 0424 7800
    FAKE_SOC=m3r FAKE_KERNEL=4.4.84-433 run status --json
    check "no LAN78xx build for M3R" dt_json "true false"
    remove_usb 1-8
    add_unclaimed 1-12 0b95 1790
    FAKE_SOC=m3r FAKE_KERNEL=4.4.84-432 run status --json
    check "LM63 on the older 05.00 firmware: its own build" has '"folder":"4.4.84-432-m3r"'
    remove_usb 1-12
    # 2017 UJ63 (K3LP, webOS 3.5): AX88772 is built in, the rest are builds to test
    add_unclaimed 1-12 0bda 8153
    FAKE_SOC=k3lp FAKE_KERNEL=4.4.3-208.drd4tv.3 run status --json
    check "UJ63 (K3LP), Realtek: a driver to test" dt_json "true true"
    check "UJ63: from its kernel's folder" has '"folder":"4.4.3-208.drd4tv.3"'
    remove_usb 1-12
    # 2017 LJ (M2R, webOS 3.5): no USB network driver at all, builds to test with a usbnet.ko
    add_unclaimed 1-12 0bda 8153
    FAKE_SOC=m2r FAKE_KERNEL=4.4.3-78.drd4tv.2 run status --json
    check "LJ (M2R), Realtek: a driver to test" dt_json "true true"
    check "LJ: from its kernel's folder" has '"folder":"4.4.3-78.drd4tv.2"'
    remove_usb 1-12
    # 2017 C7 and UJ7 (M16P, webOS 3.5): r8152 built in but too old for an RTL8153B.
    # Realtek's r8152_oot (issue #17) and ASIX's ax88179_178a (issue #18) are
    # reported working, the rest are builds to test for the M16P chip only
    add_unclaimed 1-12 0bda 8153
    FAKE_SOC=m16p FAKE_KERNEL=4.4.3-119.drd4tv.6 run status --json
    check "C7 (M16P), Realtek: the tested driver is offered" has '"driverOffer":"available"'
    remove_usb 1-12
    add_unclaimed 1-12 0b95 1790
    FAKE_SOC=m16p FAKE_KERNEL=4.4.3-119.drd4tv.6 run status --json
    check "C7 (M16P), ASIX AX88179: the tested driver is offered" has '"driverOffer":"available"'
    remove_usb 1-12
    add_unclaimed 1-12 0424 7800
    FAKE_SOC=m16p FAKE_KERNEL=4.4.3-119.drd4tv.6 run status --json
    check "C7 (M16P), Microchip LAN7800: a driver to test" dt_json "true true"
    check "C7: from its chip's folder" has '"folder":"4.4.3-119.drd4tv.6-m16p"'
    remove_usb 1-12
    # 2018 webOS 4.0: the UK63 (LM18A) and LK61 (M3) have no USB network driver
    add_unclaimed 1-10 0b95 1790
    FAKE_SOC=lm18a FAKE_KERNEL=4.4.84-636.glacier.26 run status --json
    check "UK63 (LM18A), ASIX AX88179: a driver to test" dt_json "true true"
    check "from its chip's folder" has '"folder":"4.4.84-636.glacier.26-lm18a"'
    FAKE_SOC=m3 FAKE_KERNEL=4.4.84-404.glacier.10 run status --json
    check "LK61 (M3): from its chip's folder" has '"folder":"4.4.84-404.glacier.10-m3"'
    remove_usb 1-10
    # 2018 OLEDs and NanoCells: r8152 built in, no usbnet; one build for
    # every chip on 4.4.84-150.glacier.2
    add_unclaimed 1-11 0424 7800
    FAKE_SOC=o18 FAKE_KERNEL=4.4.84-150.glacier.2 run status --json
    check "C8 (O18), LAN78xx: a driver to test" dt_json "true true"
    check "from the kernel's folder" has '"folder":"4.4.84-150.glacier.2"'
    FAKE_SOC=m16pp FAKE_KERNEL=4.4.84-150.glacier.2 run status --json
    check "SK9500 (M16PP): the same build" has '"folder":"4.4.84-150.glacier.2"'
    remove_usb 1-11
}

# 2022 UQ LCDs (LM21AN): no USB network drivers at all.  Realtek's driver
# doesn't need usbnet; ASIX comes with its own usbnet.ko
test_lm21an_drivers() {
    add_builtin
    add_unclaimed 1-1 0bda 8153
    FAKE_SOC=lm21an FAKE_KERNEL=5.4.96-934.mlt4tv.17 run status --json
    check "RTL8153: a driver to test" dt_json "true true"
    check "the newer Realtek driver first" has '"folder":"5.4.96-934.mlt4tv.17"'
    remove_usb 1-1
    add_unclaimed 1-2 17ef a387
    FAKE_SOC=lm21an FAKE_KERNEL=5.4.96-934.16.1.mirima.1 run status --json
    check "a 5.4-only Realtek id" dt_json "true true"
    remove_usb 1-2
    add_unclaimed 1-3 0b95 1790
    FAKE_SOC=lm21an FAKE_KERNEL=5.4.96-934.mlt4tv.17 run status --json
    check "ASIX: its driver, with usbnet" dt_json "true true"
}

# webOS 26 only loads modules LG signed: nothing is offered or loaded, and
# status and the report say why.  Its modules live in /usr/lib/modules.
test_webos26_signed_modules() {
    add_builtin
    mkdir -p "$SYS/module/module/parameters"
    echo Y > "$SYS/module/module/parameters/sig_enforce"
    mkdir -p "$ROOT/usr/lib/modules/6.12.44-67.18.qilian.5"
    echo "kernel/drivers/net/usb/r8152.ko" > "$ROOT/usr/lib/modules/6.12.44-67.18.qilian.5/modules.builtin"
    add_unclaimed 1-1 0b95 1790
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run status --json
    check "says signing is enforced" has '"sigEnforced":true'
    check "nothing offered" offer_is none
    check "nothing to test" dt_json "false false"
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run status
    check "status explains" has "only loads drivers signed by LG"
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run test-driver -y
    check "test-driver explains" has "only loads drivers signed by LG"
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run get-driver -y
    check "get-driver explains" has "only loads drivers signed by LG"
    fake_ko "$SB/x.ko" ax88179_178a 6.12.44-67.18.qilian.5
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run install -y --module "$SB/x.ko"
    check "install --module refused" has "only loads drivers signed by LG"
    FAKE_SOC=k26 FAKE_KERNEL=6.12.44-67.18.qilian.5 run report
    check "report says so" has "Module signing: enforced"
    check "built-ins from /usr/lib/modules" has "Built in: r8152"
}

# LM21AN kernels have no usbnet: a driver built on it brings the pinned
# usbnet.ko, which loads first (and only where the kernel lacks it)
test_driver_with_usbnet() {
    add_builtin
    drvtest_file
    add_unclaimed 1-1 0b95 1790
    echo 6c:1f:f7:00:00:02 > "$STATE/mac_1-1"
    echo "2: eth1 inet 192.168.1.43/24" > "$STATE/addr"
    local k=5.4.96-934.mlt4tv.17
    fake_ko "$STATE/download" ax88179_178a $k 0b95:1790
    fake_ko "$STATE/download_usbnet" usbnet $k
    local xs us
    xs=$(sha256sum "$STATE/download" | awk '{print $1}')
    us=$(sha256sum "$STATE/download_usbnet" | awk '{print $1}')
    # The pinned usbnet.ko doesn't match: nothing is loaded
    LGU2E_TEST_EXPERIMENTAL="https://example.test/$k/ax88179_178a.ko $xs ax88179_178a.ko $k 0b95:1790" \
        LGU2E_TEST_USBNET="https://example.test/$k/usbnet.ko 0000000000000000000000000000000000000000000000000000000000000000" \
        FAKE_SOC=lm21an FAKE_KERNEL=$k run test-driver -y
    check "bad usbnet: refused" has "usbnet.ko couldn't be downloaded and verified"
    check "bad usbnet: nothing loaded" test ! -e "$STATE/insmod.log"
    # The right one: usbnet first, then the driver, which takes the adapter
    LGU2E_TEST_EXPERIMENTAL="https://example.test/$k/ax88179_178a.ko $xs ax88179_178a.ko $k 0b95:1790" \
        LGU2E_TEST_USBNET="https://example.test/$k/usbnet.ko $us" \
        FAKE_SOC=lm21an FAKE_KERNEL=$k run test-driver -y
    check "downloaded usbnet.ko" grep -q "/$k/usbnet.ko" "$STATE/curl.log"
    check "usbnet loaded first" sh -c "head -n 1 '$STATE/insmod.log' | grep -q 'usbnet.ko'"
    check "then the driver" sh -c "sed -n 2p '$STATE/insmod.log' | grep -q 'ax88179_178a'"
    check "result works" dt_is "result=works"
    check "the report says usbnet loaded" dt_is "usbnet=loaded usbnet first: this kernel leaves it out"
}

# 4.x kernels' modules have no name= line (issues #16 and #12: AX88179 drivers
# on a C7 and a B8 failed with "unknown symbol" because usbnet.ko was never
# loaded first): the driver is still known to need usbnet by the usbnet_probe
# it calls.  The 2018 OLEDs' kernel, whose AX88179 driver is still to test
test_driver_with_usbnet_44() {
    add_builtin
    drvtest_file
    add_unclaimed 1-1 0b95 1790
    echo 6c:1f:f7:00:00:02 > "$STATE/mac_1-1"
    echo "2: eth1 inet 192.168.1.43/24" > "$STATE/addr"
    local k=4.4.84-150.glacier.2
    printf 'junk\0vermagic=%s SMP preempt mod_unload aarch64\0alias=usb:v0B95p1790d*dc*dsc*dp*ic*isc*ip*in*\0usbnet_probe\0' "$k" > "$STATE/download"
    printf 'junk\0vermagic=%s SMP preempt mod_unload aarch64\0usbnet_probe\0' "$k" > "$STATE/download_usbnet"
    local xs us
    xs=$(sha256sum "$STATE/download" | awk '{print $1}')
    us=$(sha256sum "$STATE/download_usbnet" | awk '{print $1}')
    LGU2E_TEST_EXPERIMENTAL="https://example.test/$k/ax88179_178a.ko $xs ax88179_178a.ko $k 0b95:1790" \
        LGU2E_TEST_USBNET="https://example.test/$k/usbnet.ko $us" \
        FAKE_SOC=o18 FAKE_KERNEL=$k run test-driver -y
    check "4.4: downloaded usbnet.ko" grep -q "/$k/usbnet.ko" "$STATE/curl.log"
    check "4.4: usbnet loaded first" sh -c "head -n 1 '$STATE/insmod.log' | grep -q 'usbnet.ko'"
    check "4.4: then the driver" sh -c "sed -n 2p '$STATE/insmod.log' | grep -q 'ax88179_178a'"
    check "4.4: the report says usbnet loaded" dt_is "usbnet=loaded usbnet first: this kernel leaves it out"
}

# Where the kernel has usbnet, or for Realtek's driver, no usbnet.ko is fetched
test_driver_without_usbnet() {
    add_builtin
    drvtest_file
    add_unclaimed 1-1 0b95 1790
    echo 6c:1f:f7:00:00:02 > "$STATE/mac_1-1"
    echo "2: eth1 inet 192.168.1.43/24" > "$STATE/addr"
    mkdir -p "$SYS/module/usbnet"
    local k=5.4.96-115.30.mole.2
    fake_ko "$STATE/download" ax88179_178a $k 0b95:1790
    LGU2E_TEST_EXPERIMENTAL="https://example.test/$k/ax88179_178a.ko $(sha256sum "$STATE/download" | awk '{print $1}') ax88179_178a.ko $k 0b95:1790" \
        LGU2E_TEST_USBNET="https://example.test/$k/usbnet.ko 1111111111111111111111111111111111111111111111111111111111111111" \
        FAKE_SOC=k8lp FAKE_KERNEL=$k run test-driver -y
    check "kernel has usbnet: not fetched" sh -c "! grep -q usbnet.ko '$STATE/curl.log'"
    check "result works" dt_is "result=works"
    check "the report says it's in the kernel" dt_is "usbnet=already in the kernel"
}

# At boot, a set-up driver built on usbnet loads the usbnet.ko beside it first
test_boot_loads_usbnet() {
    add_builtin
    add_unclaimed 1-1 0b95 1790
    mkdir -p "$SB/drv"
    fake_ko "$SB/drv/ax88179_178a.ko" ax88179_178a "" 0b95:1790
    fake_ko "$SB/drv/usbnet.ko" usbnet
    local us
    us=$(sha256sum "$SB/drv/usbnet.ko" | awk '{print $1}')
    LGU2E_TEST_USBNET="https://example.test/usbnet.ko $us" run install -y --module "$SB/drv/ax88179_178a.ko"
    check "installed" rc_is 0
    LGU2E_TEST_USBNET="https://example.test/usbnet.ko $us" run_hook
    check "boot still swaps" wait_log "Done: the USB adapter is eth0"
    check "usbnet loaded first" sh -c "head -n 1 '$STATE/insmod.log' | grep -q '/drv/usbnet.ko'"
    check "then the driver" sh -c "sed -n 2p '$STATE/insmod.log' | grep -q 'ax88179_178a.ko'"
}

t report test_report
t driver_with_usbnet test_driver_with_usbnet
t driver_with_usbnet_44 test_driver_with_usbnet_44
t driver_without_usbnet test_driver_without_usbnet
t boot_loads_usbnet test_boot_loads_usbnet
t webos26_signed_modules test_webos26_signed_modules
t lm21an_drivers test_lm21an_drivers
t new_chip_drivers test_new_chip_drivers
t driver_after_firmware_update test_driver_after_firmware_update
t report_builtin_driver test_report_builtin_driver
t status_builtin_driver test_status_builtin_driver
t realtek_mode_off test_realtek_mode_off
t realtek_mode_on test_realtek_mode_on
t realtek_mode_fallback test_realtek_mode_fallback
t realtek_mode_setting test_realtek_mode_setting
t status_updated_to test_status_updated_to
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
t update_app_devtemp test_update_app_devtemp
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
t toast_in_app_language test_toast_in_app_language
t toast_in_spanish test_toast_in_spanish
t boot_skips_changed_module test_boot_skips_changed_module
t driver_offer_webos5_asix test_driver_offer_webos5_asix
t get_driver_mirror test_get_driver_mirror
t driver_offer_2025_asix test_driver_offer_2025_asix
t base_vermagic_needs_known_sha test_base_vermagic_needs_known_sha
t driver_offer_k5lp test_driver_offer_k5lp
t get_driver_download_fails test_get_driver_download_fails
t get_driver_file_checked test_get_driver_file_checked
t driver_offer test_driver_offer
t driver_offer_states test_driver_offer_states
t test_driver_works test_test_driver_works
t test_driver_link_bounce test_test_driver_link_bounce
t test_driver_from_r8152 test_test_driver_from_r8152
t test_driver_no_wait test_test_driver_no_wait
t test_driver_eth0_kept test_test_driver_eth0_kept
t test_driver_no_load test_test_driver_no_load
t test_driver_crashed test_test_driver_crashed
t test_driver_checks test_test_driver_checks
t test_driver_k6lp test_test_driver_k6lp
t test_driver_unclaimed test_test_driver_unclaimed

[ -n "${BBDIR:-}" ] && rm -rf "$BBDIR"
echo
echo "$MODE: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || { echo "Failed:$FAILED_NAMES"; exit 1; }
