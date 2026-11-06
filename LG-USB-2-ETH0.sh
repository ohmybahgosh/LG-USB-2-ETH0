#!/bin/sh

###############################################################################
# LG-USB-2-ETH0                                                               #
# Makes a USB Ethernet adapter the TV's eth0 on rooted LG webOS TVs           #
# Author: OhMyBahGosh                                                         #
# https://github.com/ohmybahgosh/LG-USB-2-ETH0                                #
###############################################################################
#
# Usage: sh LG-USB-2-ETH0.sh [command] [options]
#        Run with no arguments for the menu, or with --help for everything.

VERSION="2.4.14"

# === Color Codes ===
# Off when the output isn't a terminal (logs, pasted reports) or NO_COLOR is set
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# === Paths ===
# LGU2E_ROOT and LGU2E_SYSFS are for testing only. Leave them unset on the TV.
INIT_DIR="${LGU2E_ROOT}/var/lib/webosbrew/init.d"
# Same name as v1, so upgrading replaces the old hook
HOOK="$INIT_DIR/S01fix-eth"
# A disabled hook is kept outside init.d. The Homebrew Channel starts init.d
# with run-parts, and busybox run-parts still runs names like *.disabled.
DISABLED_HOOK="${LGU2E_ROOT}/var/lib/webosbrew/S01fix-eth.disabled"
# Where v1 put a disabled hook (inside init.d, so it may have kept running)
OLD_DISABLED_HOOK="$INIT_DIR/S01fix-eth.disabled"
# Settings for the boot hook. The hook itself is a symlink to this script.
CONF="${LGU2E_ROOT}/var/lib/webosbrew/lg-usb-2-eth0.conf"
# Small log kept with the Homebrew Channel's files, as its guidelines ask
LOG_FILE="${LGU2E_ROOT}/var/lib/webosbrew/lg-usb-2-eth0.log"
# Per-boot state (RAM): background job PID, takeover tries, live-switch output
RUN_DIR="${LGU2E_ROOT}/tmp"
PID_FILE="$RUN_DIR/lg-usb-2-eth0.pid"
# Where a copy of the script lives when it isn't run from the TV app
SCRIPT_HOME="${LGU2E_ROOT}/home/root/lg-usb-2-eth0"
OS_INFO="${LGU2E_ROOT}/var/run/nyx/os_info.json"
HBC_DIR="/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service"
MARKER="Managed by LG-USB-2-ETH0"
# Where get-driver keeps downloaded driver modules (persistent storage)
DRIVER_DIR="${LGU2E_ROOT}/home/root/lg-usb-2-eth0/drivers"
# test-driver: drivers this project built from LG's kernel source that
# haven't run on a TV yet, kept in the mirror's experimental folder at a
# fixed commit.  test-driver only ever loads one until the next restart.
# How the test went is kept across a restart, so a test that froze the TV
# is still reported.
EXPERIMENTAL_URL="https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/ba8b39bca15440725f15143320cc7edf15a47e51/experimental"
DRVTEST_FILE="${LGU2E_ROOT}/var/lib/webosbrew/lg-usb-2-eth0.drvtest"
DRVTEST_FORM="https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=driver-test.yml"
# DonZoomik's own boot hook for r8152_oot, which does the same job as --module
AUTOBIND_HOOK="$INIT_DIR/90-r8152-oot"
# Updates: the latest GitHub release, and the Homebrew Channel repo that
# also serves the TV app.  The Homebrew Channel keeps its settings (the
# repos you added) in its web storage.
APP_ID="org.ohmybahgosh.lgusb2eth0"
RELEASES="${LGU2E_RELEASES:-https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases}"
REPO_URL="https://ohmybahgosh.dev/repo"
HBC_STORAGE="${LGU2E_ROOT}/var/lib/wam/Default/Local Storage/leveldb"
# Kept while --wifi-fallback has turned Wi-Fi on, so it's turned off again
# once the cable works, even after a reboot in between
WIFI_MARK="${LGU2E_ROOT}/var/lib/webosbrew/lg-usb-2-eth0.wifi"
# --block-updates: what webOS's own update switch was before it was turned
# off, so turning the option off puts it back
UPD_MARK="${LGU2E_ROOT}/var/lib/webosbrew/lg-usb-2-eth0.updates"
HOSTS_FILE="${LGU2E_HOSTS:-/etc/hosts}"
# shellcheck disable=SC2034 # used by updates_block, in CORE
SWUPDATE_DIR="${LGU2E_ROOT}/mnt/lg/cmn_data/swupdate"

# === Defaults (install options) ===
ASSUME_YES=0
APPLY_NOW=0
PIN_MAC=""
WAIT_SECS=120
PARK_NAME="eth2"
MODULE=""
DRIVER=""
# SHA-256 of the module file, saved at install and checked before every load
MODULE_SHA=""
WATCH=0
WIFI_FALLBACK=0
BLOCK_UPDATES=0
# Which options were given on the command line. Anything not given keeps its
# current setting when 'install' is run again.
SET_MAC=0 SET_WAIT=0 SET_MODULE=0 SET_WATCH=0 SET_WIFI=0 SET_BLOCK=0 SET_RTK=0
JSON=0
PHASE=""
CHECK_ONLY=0
DRIVER_FILE=""
LAST=0
NO_WAIT=0

# === Helper Functions ===
log() { printf '%b%s%b\n' "$1" "$2" "$NC"; }
error_exit() { log "$RED" "[ERROR] $1"; exit 1; }
success() { log "$GREEN" "[SUCCESS] $1"; }
warn() { log "$YELLOW" "[WARNING] $1"; }
info() { log "$CYAN" "[INFO] $1"; }
# Read one answer into ANSWER. Uses the terminal even when the script is
# piped in (wget -O- ... | sh), and fails when there is no terminal at all.
read_answer() {
    ANSWER=""
    printf '%b%s%b' "$YELLOW" "$1" "$NC"
    if [ -t 0 ]; then
        read -r ANSWER
    elif ( : < /dev/tty ) 2>/dev/null; then
        read -r ANSWER < /dev/tty
    else
        echo
        return 1
    fi
}
confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    if ! read_answer "$1 [y/N]: "; then
        warn "No terminal to answer on. Add -y to answer yes."
        return 1
    fi
    [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]
}

usage() {
    cat <<EOF
LG-USB-2-ETH0 v$VERSION: make a USB Ethernet adapter the TV's eth0

Usage: sh LG-USB-2-ETH0.sh [command] [options]

Commands (no command opens the menu):
  install     Add the boot hook that swaps the adapter in at every boot
  uninstall   Remove the boot hook (add --now to also swap back right away)
  enable      Turn a disabled boot hook back on
  disable     Keep the boot hook but stop it running at boot
  apply       Swap the adapter in now, without touching the boot hook
  revert      Give eth0 back to the built-in port now
  status      Show the hook, the network interfaces and any problems
  doctor      Same as status
  report      Print a short report to paste into a GitHub issue
  update      Check for a newer release and install it.  With --check,
              only say whether there is one
  speedtest   Measure latency, download and upload speed through the TV's
              current connection, against Cloudflare's nearest server
  get-driver  Download a better driver module known to work on this exact
              kernel, if there is one, and check its checksum. With
              --file PATH, check and use a copy you downloaded yourself
  test-driver Try a new, not yet tested driver built for this exact
              kernel, if there is one: download and check it, load it
              until the next restart, move the adapter to it, and show a
              report to send.  With --last, show the last test's report
  version     Print the version

Options:
  -y, --yes          Answer yes to every question
  --now              With install or uninstall, also swap right away
  --mac MAC          Only ever promote the adapter with this MAC address
  --wait SECONDS     How long the boot hook waits for the adapter (default 120)
  --module FILE.ko   Load this driver module at boot, and move the adapter
                     from the generic cdc_ncm driver over to it
  --watch            Keep watching after boot: swap the adapter in when it is
                     plugged in, and give eth0 back when it is unplugged
  --wifi-fallback    Turn Wi-Fi on if eth0 loses its cable link for a minute,
                     and off again once the cable works.  Only when Wi-Fi was
                     off, and only Wi-Fi networks the TV already knows
  --block-updates    Block firmware updates more thoroughly, on top of the
                     Homebrew Channel's own block: turn webOS's update check
                     off, block the update servers it misses, and the one
                     it reaches by IP.  Updates can remove root for good
  --no-realtek-mode  Don't switch Realtek adapters to their Realtek mode.
                     By default, a Realtek RTL8152 or RTL8153 adapter that
                     the kernel left on the generic driver is switched over
                     to the kernel's own r8152, when it has one
  --no-watch, --no-module, --no-mac, --no-wifi-fallback, --no-block-updates
                     Turn that setting off again (--realtek-mode turns it on)
  --json             With status or speedtest: machine-readable output (used
                     by the TV app)
  --phase PHASE      With speedtest: run only ping, down or up
  --check            With update: only check, don't install

Running 'install' again keeps every setting you don't change.
  -h, --help         Show this help
EOF
}

# === Core ===
# Everything in CORE is also written into the boot hook, so the hook works
# on its own and needs nothing else from this script.
CORE=$(cat <<'CORE_EOF'
# LGU2E_SYSFS only exists so the script can be tested against a fake /sys
NET=${LGU2E_SYSFS:-/sys}/class/net
USB_DEVS=${LGU2E_SYSFS:-/sys}/bus/usb/devices
SYS_MODULES=${LGU2E_SYSFS:-/sys}/module
USB_DRIVERS=${LGU2E_SYSFS:-/sys}/bus/usb/drivers
# Seconds to let a new adapter settle, and between checks in --watch mode
SETTLE_SECS=${LGU2E_SETTLE:-3}
WATCH_EVERY=${LGU2E_WATCH_EVERY:-5}
# --wifi-fallback: seconds without a cable link before Wi-Fi goes on, and
# seconds of a working link before it goes off again
WIFI_GRACE=${LGU2E_WIFI_GRACE:-60}
WIFI_BACK_SECS=${LGU2E_WIFI_BACK:-30}
# After standby: seconds to let webOS bring the network back up before the
# adapter moves to the faster driver, and to wait for it to reconnect after
NET_SETTLE=${LGU2E_NET_SETTLE:-30}
NET_CHECK=${LGU2E_NET_CHECK:-30}
# Realtek mode (on unless --no-realtek-mode): switch a Realtek adapter the
# kernel left in its standard NCM or ECM mode to its Realtek mode, so the
# kernel's own r8152 takes it.  How the last try went is kept for status.
REALTEK_MODE=${REALTEK_MODE:-${LGU2E_REALTEK_MODE:-1}}
REALTEK_STATE=${RUN_DIR:-/tmp}/lg-usb-2-eth0.realtek

sysval() { [ -r "$1" ] && IFS= read -r _v < "$1" 2>/dev/null && printf '%s\n' "$_v"; }

is_wifi() { [ -d "$NET/$1/wireless" ] || [ -e "$NET/$1/phy80211" ]; }

nic_driver() {
    _l=$(readlink "$NET/$1/device/driver" 2>/dev/null) || return 0
    _l=${_l##*/}
    # Some Wi-Fi modules hang off the USB device itself, whose driver is just
    # "usb". The real driver is on one of its interfaces. Combo chips also
    # have Bluetooth, audio or HID interfaces, so skip those.
    if [ "$_l" = usb ]; then
        for _d in "$NET/$1/device"/*:*/driver; do
            [ -e "$_d" ] || continue
            _x=$(readlink "$_d")
            case "${_x##*/}" in bt*|*bluetooth*|usbhid|snd-usb-audio|uvcvideo) continue ;; esac
            _l=${_x##*/}
            break
        done
    fi
    echo "$_l"
}

nic_mac() { sysval "$NET/$1/address" | tr 'A-F' 'a-f'; }

# True for a real wired network device that hangs off the USB bus.
# Wi-Fi is excluded on purpose: many LG Wi-Fi modules are USB devices too.
# Phone tethering and modem drivers are excluded as well.
is_usb_nic() {
    [ -e "$NET/$1/device" ] || return 1
    [ "$(sysval "$NET/$1/type")" = 1 ] || return 1
    is_wifi "$1" && return 1
    case "$(nic_driver "$1")" in rndis_host|ipheth|cdc_mbim|qmi_wwan) return 1 ;; esac
    [ -r "$NET/$1/device/../idVendor" ] && return 0
    case "$(readlink "$NET/$1/device/subsystem" 2>/dev/null)" in */usb) return 0 ;; esac
    return 1
}

# True for the TV's own wired port (a device-backed, non-USB, non-Wi-Fi NIC)
is_builtin_nic() {
    [ -e "$NET/$1/device" ] || return 1
    [ "$(sysval "$NET/$1/type")" = 1 ] || return 1
    is_wifi "$1" && return 1
    is_usb_nic "$1" && return 1
    return 0
}

# The USB adapter to promote: the pinned MAC if one is set, otherwise the
# first USB NIC with a cable in, otherwise the first USB NIC at all.
find_usb_nic() {
    _first=""
    for _p in "$NET"/*; do
        _n=${_p##*/}
        is_usb_nic "$_n" || continue
        if [ -n "$PIN_MAC" ]; then
            [ "$(nic_mac "$_n")" = "$PIN_MAC" ] && { echo "$_n"; return 0; }
            continue
        fi
        [ "$(sysval "$_p/carrier" 2>/dev/null)" = 1 ] && { echo "$_n"; return 0; }
        [ -n "$_first" ] || _first=$_n
    done
    [ -n "$_first" ] && echo "$_first"
    return 0
}

# The built-in port, wherever it is right now (eth0, or parked as ethN)
find_builtin_nic() {
    is_builtin_nic eth0 && { echo eth0; return 0; }
    for _p in "$NET"/eth*; do
        _n=${_p##*/}
        is_builtin_nic "$_n" && { echo "$_n"; return 0; }
    done
    return 0
}

free_eth_name() {
    [ -e "$NET/$1" ] || { echo "$1"; return 0; }
    for _i in 1 2 3 4 5 6 7 8 9; do
        [ -e "$NET/eth$_i" ] || { echo "eth$_i"; return 0; }
    done
    return 1
}

# Rename an interface. It has to be down first, and webOS's connection manager
# sometimes brings it straight back up ("Device or resource busy"), so retry.
rename_if() {
    _try=1
    while :; do
        _err=""
        if ip link set dev "$1" down 2>/dev/null && _err=$(ip link set dev "$1" name "$2" 2>&1); then
            return 0
        fi
        [ "$_try" -ge 3 ] && break
        _try=$((_try + 1))
        sleep 1
    done
    echo "Renaming $1 to $2 failed after 3 tries${_err:+: $_err}"
    return 1
}

# Make the USB adapter eth0 and park the built-in port under another name.
# Puts the old names back if a step fails, so the TV never ends up with the
# built-in port renamed and nothing called eth0.
swap_in() {
    _usb=$(find_usb_nic)
    if [ -z "$_usb" ]; then
        echo "No USB Ethernet adapter found${PIN_MAC:+ with MAC $PIN_MAC}. Nothing changed."
        return 2
    fi
    if [ "$_usb" = eth0 ]; then
        echo "The USB adapter is already eth0. Nothing to do."
        return 0
    fi
    if [ -e "$NET/eth0" ] && ! is_builtin_nic eth0; then
        echo "eth0 is not the built-in port, so it is left alone. Nothing changed."
        return 1
    fi
    _park=""
    if [ -e "$NET/eth0" ]; then
        _park=$(free_eth_name "${PARK_NAME:-eth2}") || { echo "No free ethN name to park the built-in port."; return 1; }
        echo "Built-in eth0 -> $_park"
        if ! rename_if eth0 "$_park"; then
            ip link set dev eth0 up 2>/dev/null
            echo "Could not rename the built-in port. Nothing changed."
            return 1
        fi
    fi
    echo "USB $_usb ($(nic_driver "$_usb")) -> eth0"
    if ! rename_if "$_usb" eth0; then
        echo "Could not rename $_usb. Putting the old names back."
        ip link set dev "$_usb" up 2>/dev/null
        if [ -n "$_park" ]; then
            ip link set dev "$_park" name eth0 2>/dev/null
            ip link set dev eth0 up 2>/dev/null
        fi
        return 1
    fi
    ip link set dev eth0 up
    [ -n "$_park" ] && ip link set dev "$_park" up
    echo "Done: the USB adapter is eth0${_park:+, the built-in port is $_park}."
    return 0
}

# Give eth0 back to the built-in port, and the adapter the first free ethN
swap_out() {
    _bi=$(find_builtin_nic)
    if [ -z "$_bi" ]; then
        echo "No built-in wired port found. Nothing changed."
        return 2
    fi
    if [ "$_bi" = eth0 ]; then
        echo "The built-in port is already eth0. Nothing to do."
        return 0
    fi
    _tmp=""
    if [ -e "$NET/eth0" ]; then
        if ! rename_if eth0 ethusbtmp; then
            ip link set dev eth0 up 2>/dev/null
            echo "Could not rename eth0. Nothing changed."
            return 1
        fi
        _tmp=ethusbtmp
    fi
    echo "Built-in $_bi -> eth0"
    if ! rename_if "$_bi" eth0; then
        echo "Could not rename $_bi. Putting the old names back."
        ip link set dev "$_bi" up 2>/dev/null
        if [ -n "$_tmp" ]; then
            ip link set dev "$_tmp" name eth0 2>/dev/null
            ip link set dev eth0 up 2>/dev/null
        fi
        return 1
    fi
    ip link set dev eth0 up
    if [ -n "$_tmp" ]; then
        _new=$(free_eth_name eth1) || _new=ethusb
        ip link set dev "$_tmp" name "$_new" && ip link set dev "$_new" up
        echo "USB adapter -> $_new"
    fi
    echo "Done: the built-in port is eth0 again."
    return 0
}

# Write to a sysfs file. LGU2E_SYSWRITE only exists for the test suite.
sys_write() {
    if [ -n "$LGU2E_SYSWRITE" ]; then "$LGU2E_SYSWRITE" "$1" "$2"; else printf '%s' "$2" > "$1"; fi
}

# The kernel a .ko file was built for (its vermagic), read without modinfo
module_kernel() {
    tr -c '[:alnum:]_=.+ -' '\n' < "$1" 2>/dev/null | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | head -n 1
}

# Better driver modules known to work on one exact kernel, as
# "url sha256 file author-page". They're built and published by their
# authors. get-driver checks the SHA-256 before keeping a download.
# known_driver KERNEL: "url sha256 file page ids mirror" for a driver module
# known to work on exactly that kernel.  Each one is pinned to a fixed commit
# and kept only if its SHA-256 matches.  ids are the USB adapters the module
# supports (from its own aliases): it's only offered when one is plugged in.
# mirror is a byte-for-byte copy in ohmybahgosh/lg-webos-usb-drivers, also at
# a fixed commit, tried only if the author's download fails.
known_driver() {
    _kdo=$(known_exact "$1"; known_by_soc "$1"; tested_driver "$1"; [ -n "${LGU2E_TEST_DRIVER:-}" ] && echo "$LGU2E_TEST_DRIVER")
    [ -n "$_kdo" ] || return 1
    echo "$_kdo"
}

known_exact() {
    case "$1" in
        5.4.268-329.ptl4tv.5)
            # DonZoomik's build of Realtek's v2.22.1 driver (2022 C2, 2024 C4 on webOS 25)
            echo "https://raw.githubusercontent.com/DonZoomik/webos-r8152/1ea8e98a24ef7443c590024d48947fee22d29cf1/r8152_oot.ko fe1691622747c106af44f7834675ec75ca3327a797c6bbec394e2998db66e8cb r8152_oot.ko https://github.com/DonZoomik/webos-r8152 045e:07ab,045e:07c6,045e:0927,045e:0c5e,04e8:a101,0955:09ff,0b05:1976,0b05:1d91,0bda:8050,0bda:8053,0bda:8152,0bda:8153,0bda:8155,0bda:8156,0bda:8157,0bda:815a,13b1:0041,17ef:304f,17ef:3052,17ef:3054,17ef:3057,17ef:3062,17ef:3069,17ef:3082,17ef:3098,17ef:7205,17ef:720a,17ef:720b,17ef:720c,17ef:7214,17ef:721e,17ef:8153,17ef:a359,17ef:a387,2357:0601,2baf:0012 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/5.4.268-329.ptl4tv.5/r8152_oot.ko" ;;
        5.4.268-294.17.paparoa.pine.2)
            # mbenitez343's build of the kernel's own r8152 v1.10.11, for 2024
            # QNED and OLED (K25lp / Paparoa) on webOS 25, where LG removed
            # it.  Gigabit RTL8152/RTL8153 adapters only, not 2.5G ones.
            echo "https://raw.githubusercontent.com/mbenitez343/lg-webos-2024-ethernet-fix/05ad4588bbdf91825567726713650c4f4bf13fdc/r8152.ko 7c7c32586fabf4a65899362594a130923d01cb90309c209e04c45d91840273ba r8152.ko https://github.com/mbenitez343/lg-webos-2024-ethernet-fix 045e:07ab,045e:07c6,045e:0927,04e8:a101,0955:09ff,0bda:8050,0bda:8152,0bda:8153,13b1:0041,17ef:304f,17ef:3054,17ef:3062,17ef:3069,17ef:7205,17ef:720c,17ef:7214,17ef:721e,17ef:a387,2357:0601 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/5.4.268-294.17.paparoa.pine.2/r8152.ko" ;;
        4.4.84-612.jcl4tv.40)
            # OCT0PUSCRIME's build of ASIX's own AX88179/178A driver (v1.19.0),
            # for webOS 5 (2020 UN7300), whose kernel has no ASIX driver
            echo "https://raw.githubusercontent.com/OCT0PUSCRIME/lg-webos-ax88179-driver/734b54c9489034886382a23625b753aab9e661de/ax88179_178a.ko c9aefe84ee61d7021d739af37d70214a4b82f4b449a5eaf3501cec1f21af1831 ax88179_178a.ko https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver 04e8:a100,0711:0179,0930:0a13,0b95:178a,0b95:1790,0df6:0072,17ef:304b,2001:4a00 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/4.4.84-612.jcl4tv.40/ax88179_178a.ko" ;;
        5.4.268-294.24.papikonda.2)
            # dd3git's build of the ASIX driver from LG's kernel source, for
            # the K24 chip (tested on a 2025 B5).  Its vermagic says only
            # 5.4.268, so module_fits accepts it by its SHA-256.
            echo "https://raw.githubusercontent.com/dd3git/lg-webos-ax88179-driver/3a871c9ef7b21bdbc6d93dd2ca2bd07d94c08d37/ax88179_178a.ko f75802cfeca28381c9cf990e589f34bc21129d643408c40ca56b11b9ff1c1987 ax88179_178a.ko https://github.com/dd3git/lg-webos-ax88179-driver 04b4:3610,04e8:a100,050d:0128,0b95:178a,0b95:1790,0df6:0072,17ef:304b,2001:4a00 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/5.4.268-294.24.papikonda.2/ax88179_178a.ko" ;;
    esac
    return 0
}

# Drivers built per chip (SoC) rather than per exact kernel.  Their vermagic
# carries only the base version (like 4.4.84), so the chip is checked too.
known_by_soc() {
    case "$(tv_soc)" in
        k5lp)
            case "$1" in
                4.4.84|4.4.84-*)
                    # throwaway96's builds of the kernel's own drivers for K5Lp
                    echo "https://raw.githubusercontent.com/throwaway96/webos-kernel-drivers/67cb647be62a0d516fc1e5ead24ce2f967a44bbd/armv7l-4.4.84-k5lp/drivers/net/usb/r8152.ko 4735b94db05247a1b3f2d40a25179abfc4b06c60692e4a8edacc888df16ad9c4 r8152.ko https://github.com/throwaway96/webos-kernel-drivers 04e8:a101,0955:09ff,0bda:8152,0bda:8153,17ef:304f,17ef:7205 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/k5lp-4.4.84/r8152.ko"
                    echo "https://raw.githubusercontent.com/throwaway96/webos-kernel-drivers/67cb647be62a0d516fc1e5ead24ce2f967a44bbd/armv7l-4.4.84-k5lp/drivers/net/usb/ax88179_178a.ko dabd33606f30197d1eb58e7c8b02549ebcca3a8015504da6b0d6c2fb97c711fd ax88179_178a.ko https://github.com/throwaway96/webos-kernel-drivers 04e8:a100,0b95:178a,0b95:1790,0df6:0072,17ef:304b,2001:4a00 https://raw.githubusercontent.com/ohmybahgosh/lg-webos-usb-drivers/b8970e766062d0086520aecb96a6c8343cea1f72/drivers/k5lp-4.4.84/ax88179_178a.ko" ;;
            esac ;;
    esac
    return 0
}

# The TV's chip (SoC), lowercase, like k5lp or o22
tv_soc() {
    command -v nyx-cmd >/dev/null 2>&1 || return 0
    { if command -v timeout >/dev/null 2>&1; then timeout 5 nyx-cmd DeviceInfo query device_name; else nyx-cmd DeviceInfo query device_name; fi; } 2>/dev/null | head -n 1 | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_'
}

# module_fits FILE: FILE is built for the kernel running now.  Its vermagic
# names this kernel, or it's a known driver for this kernel by SHA-256 (some
# builds carry only the base version, like 5.4.268, and the TV loads them).
module_fits() {
    _mfk=$(module_kernel "$1")
    if [ -z "$_mfk" ] || [ "$_mfk" = "$(uname -r)" ]; then return 0; fi
    command -v sha256sum >/dev/null 2>&1 || return 1
    _mfs=$(sha256sum "$1" | awk '{print $1}')
    known_driver "$(uname -r)" | awk -v s="$_mfs" '$2 == s {f = 1} END {exit !f}'
}

# Load the --module driver, but only if it's the exact file that was
# installed and it was built for the kernel running now. A firmware update
# can change the kernel while root survives; loading a module built for
# another kernel can crash the TV, so it's skipped instead.
load_module() {
    [ -n "$MODULE" ] || return 0
    _m=${DRIVER:-${MODULE##*/}}
    _m=${_m%.ko}
    _mk=""
    [ -r "$MODULE" ] && _mk=$(module_kernel "$MODULE")
    if [ -d "$SYS_MODULES/$_m" ]; then
        echo "Module $_m already loaded."
    elif [ ! -r "$MODULE" ]; then
        echo "Module file $MODULE is missing. Skipping it."
    elif ! module_fits "$MODULE"; then
        echo "Not loading $MODULE: it's built for kernel $_mk, but the TV now runs $(uname -r) (a firmware update?). The adapter stays on its current driver."
    elif [ -n "$MODULE_SHA" ] && command -v sha256sum >/dev/null 2>&1 && \
         [ "$(sha256sum "$MODULE" | awk '{print $1}')" != "$MODULE_SHA" ]; then
        echo "Not loading $MODULE: the file changed since it was installed. Run install again if that was you."
    elif insmod "$MODULE"; then
        echo "Loaded module $MODULE."
    else
        echo "insmod $MODULE failed (built for another kernel?). See dmesg. Carrying on without it."
    fi
}

# True when any interface of USB device $1 is bound to $DRIVER
on_driver() {
    for _i in "$USB_DEVS/$1"/*:*; do
        [ "$(nic_driver_path "$_i")" = "${2:-$DRIVER}" ] && return 0
    done
    return 1
}
nic_driver_path() { _l=$(readlink "$1/driver" 2>/dev/null) && echo "${_l##*/}"; }

# Turn off scatter-gather on adapters run by $DRIVER. On LG's xHCI it makes
# the TV's USB controller hang after a while (found by DonZoomik).
disable_sg() {
    for _p in "$NET"/*; do
        _f="$_p/rtl_adv/sg_en"
        [ -w "$_f" ] || continue
        [ "$(nic_driver "${_p##*/}")" = "$DRIVER" ] || continue
        [ "$(sysval "$_f")" = disable ] || sys_write "$_f" disable 2>/dev/null
    done
    return 0
}

# Driver takeover. The kernel gives many Realtek adapters to a generic
# driver (cdc_ncm, or cdc_ether when the kernel has no Realtek driver at all),
# even when a better driver module is loaded. Move each one over to $DRIVER.
# If that doesn't take within a few seconds, give it back. Each device gets
# one try per boot, so a driver that doesn't support it can't cause repeated
# drops.
#
# Only devices the module says it supports (its USB IDs) are moved, so a phone
# tethered over cdc_ether is never touched.  A module that lists no IDs is
# trusted with cdc_ncm only, as before.
TAKEOVER_STATE=${RUN_DIR:-/tmp}/lg-usb-2-eth0.takeover
GENERIC_DRIVERS="cdc_ncm cdc_ether"

# module_ids FILE: the vid:pid pairs a .ko declares, lowercase, space-separated
module_ids() {
    tr -c '[:alnum:]_=:*' '\n' < "$1" 2>/dev/null | sed -n 's/^alias=usb:v\([0-9A-Fa-f]\{4\}\)p\([0-9A-Fa-f]\{4\}\).*/\1:\2/p' \
        | tr 'A-F' 'a-f' | sort -u | tr '\n' ' '
}

# Read once and kept: the module file can't change under us (its checksum
# was checked before it was loaded)
TAKEOVER_IDS=""
TAKEOVER_IDS_READ=0
takeover_ids() {
    [ "$TAKEOVER_IDS_READ" = 1 ] && return 0
    TAKEOVER_IDS_READ=1
    [ -n "$MODULE" ] && [ -r "$MODULE" ] && TAKEOVER_IDS=$(module_ids "$MODULE")
    return 0
}

# takeover_fits NAME: NAME is on a generic driver and $DRIVER should get it.
# Sets _gd to the generic driver and _tok to the device's one-try token.
takeover_fits() {
    _gd=$(nic_driver "$1")
    case " $GENERIC_DRIVERS " in *" $_gd "*) ;; *) return 1 ;; esac
    _ifc=$(readlink -f "$NET/$1/device") || return 1
    _in=${_ifc##*/}
    _dev=${_in%%:*}
    _vid=$(sysval "$USB_DEVS/$_dev/idVendor"); _pid=$(sysval "$USB_DEVS/$_dev/idProduct")
    _tok="$(sysval "$USB_DEVS/$_dev/busnum"):$(sysval "$USB_DEVS/$_dev/devnum"):$_vid:$_pid"
    takeover_ids
    if [ -n "$TAKEOVER_IDS" ]; then
        case " $TAKEOVER_IDS " in *" $_vid:$_pid "*) return 0 ;; *) return 1 ;; esac
    fi
    [ "$_gd" = cdc_ncm ]
}

# Realtek mode.  Many Realtek adapters have a Realtek-only USB configuration
# (the first) and a standard NCM or ECM one.  Kernels before 5.11 pick the
# standard one, so cdc_ncm or cdc_ether takes the adapter even when r8152 is
# built in (like on a 2019 C9, kernel 4.4), and r8152 can't claim it in that
# mode.  Newer kernels switch it back on their own; this does the same.  One
# try per plug-in, and if r8152 doesn't take it within 5 s, the adapter goes
# back to the configuration it was in, and status suggests a driver from
# get-driver or test-driver instead.  Only with REALTEK_MODE=1 and no driver
# module of our own (take_over handles those).
realtek_mode() {
    [ "$REALTEK_MODE" = 1 ] || return 0
    [ -z "$DRIVER" ] || return 0
    [ -d "$USB_DRIVERS/r8152" ] || return 0
    for _p in "$NET"/*; do
        _n=${_p##*/}
        is_usb_nic "$_n" || continue
        _gd=$(nic_driver "$_n")
        case " $GENERIC_DRIVERS " in *" $_gd "*) ;; *) continue ;; esac
        _ifc=$(readlink -f "$NET/$_n/device") || continue
        _in=${_ifc##*/}
        _dev=${_in%%:*}
        _vid=$(sysval "$USB_DEVS/$_dev/idVendor"); _pid=$(sysval "$USB_DEVS/$_dev/idProduct")
        case "$_vid:$_pid" in 0bda:8152|0bda:8153) ;; *) continue ;; esac
        _cfg=$(sysval "$USB_DEVS/$_dev/bConfigurationValue")
        [ -n "$_cfg" ] && [ "$_cfg" != 1 ] || continue
        _ncf=$(sysval "$USB_DEVS/$_dev/bNumConfigurations")
        case "$_ncf" in ''|*[!0-9]*) continue ;; esac
        [ "$_ncf" -ge 2 ] || continue
        _tok="cfg:$(sysval "$USB_DEVS/$_dev/busnum"):$(sysval "$USB_DEVS/$_dev/devnum"):$_vid:$_pid"
        grep -qx "$_tok" "$TAKEOVER_STATE" 2>/dev/null && continue
        echo "$_tok" >> "$TAKEOVER_STATE"
        echo "USB $_n ($_dev, $_vid:$_pid): $_gd -> r8152, switching it from USB configuration $_cfg to its Realtek mode (1)"
        if ! sys_write "$USB_DEVS/$_dev/bConfigurationValue" 1 2>/dev/null; then
            echo "Could not switch it. Leaving it as it is."
            continue
        fi
        _t=0
        while [ "$_t" -lt 5 ] && ! on_driver "$_dev" r8152; do sleep 1; _t=$((_t + 1)); done
        if on_driver "$_dev" r8152; then
            echo "Now on r8152."
            echo "ok $_vid:$_pid" > "$REALTEK_STATE"
            continue
        fi
        echo "r8152 did not take it. Putting it back in USB configuration $_cfg."
        echo "failed $_vid:$_pid" > "$REALTEK_STATE"
        sys_write "$USB_DEVS/$_dev/bConfigurationValue" "$_cfg" 2>/dev/null
    done
    return 0
}

take_over() {
    realtek_mode
    [ -n "$DRIVER" ] || return 0
    if [ ! -d "$USB_DRIVERS/$DRIVER" ]; then
        echo "Driver $DRIVER is not loaded, so the adapter stays on its current driver."
        return 0
    fi
    for _p in "$NET"/*; do
        _n=${_p##*/}
        is_usb_nic "$_n" || continue
        takeover_fits "$_n" || continue
        grep -qx "$_tok" "$TAKEOVER_STATE" 2>/dev/null && continue
        echo "$_tok" >> "$TAKEOVER_STATE"
        echo "USB $_n ($_dev, $_vid:$_pid): $_gd -> $DRIVER"
        if ! sys_write "$USB_DRIVERS/$_gd/unbind" "$_in" 2>/dev/null; then
            echo "Could not release it from $_gd. Leaving it as it is."
            continue
        fi
        # The driver may switch the adapter's USB configuration, which makes
        # the bind look like it failed even when it worked, so check after.
        sys_write "$USB_DRIVERS/$DRIVER/bind" "$_in" 2>/dev/null
        _t=0
        while [ "$_t" -lt 5 ] && ! on_driver "$_dev"; do sleep 1; _t=$((_t + 1)); done
        if on_driver "$_dev"; then
            echo "Now on $DRIVER."
            continue
        fi
        echo "$DRIVER did not take it. Giving it back to $_gd."
        [ -d "$_ifc" ] && sys_write "$USB_DRIVERS/$_gd/bind" "$_in" 2>/dev/null
    done
    disable_sg
    return 0
}

# Wait up to 10 s for a USB network device to come back after a takeover
wait_for_nic() {
    _t=0
    while [ "$_t" -lt 10 ] && [ -z "$(find_usb_nic)" ]; do sleep 1; _t=$((_t + 1)); done
}

# --watch: keep following the adapter after boot. Plugged in: swap it in.
# Unplugged: give eth0 back to the built-in port, so the TV is never left
# without an eth0. Logs only when something happens.
# True when an adapter is on cdc_ncm and hasn't had its one try yet. A new
# USB enumeration (after standby, a USB reset or a replug) counts as new.
takeover_pending() {
    for _p in "$NET"/*; do
        _n=${_p##*/}
        is_usb_nic "$_n" || continue
        takeover_fits "$_n" || continue
        grep -qx "$_tok" "$TAKEOVER_STATE" 2>/dev/null || return 0
    done
    return 1
}

iface_ipv4() { ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4; exit}'; }

# test-driver's detached part: load $MODULE, move the adapter to $DRIVER,
# and write how it went to $DRVTEST_FILE (key=value lines).  It runs
# detached because moving the adapter can drop the session that started it.
drv_try() {
    _dtl=$(dmesg 2>/dev/null | wc -l)
    _dte=""
    if [ -d "$SYS_MODULES/$DRIVER" ]; then
        _dtd=already
    elif _dte=$(insmod "$MODULE" 2>&1); then
        _dtd=yes
    else
        _dtd=no
    fi
    echo "Loading $DRIVER: $_dtd${_dte:+ ($_dte)}"
    if [ "$_dtd" != no ]; then
        rm -f "$TAKEOVER_STATE"
        take_over
        wait_for_nic
        [ "${DRVTEST_SWAP:-0}" = 1 ] && swap_in
        # Give webOS time to bring the network up on it
        _dtt=0
        while [ "$_dtt" -lt "$NET_CHECK" ]; do
            _dtn=$(find_usb_nic)
            [ -n "$_dtn" ] && [ -n "$(iface_ipv4 "$_dtn")" ] && break
            sleep 2
            _dtt=$((_dtt + 2))
        done
    fi
    _dtn=$(find_usb_nic)
    _dtv="" _dtc="" _dts="" _dta=no _dtp=""
    if [ -n "$_dtn" ]; then
        _dtv=$(nic_driver "$_dtn")
        _dtc=$(sysval "$NET/$_dtn/carrier" 2>/dev/null)
        _dts=$(sysval "$NET/$_dtn/speed" 2>/dev/null)
        if [ -n "$(iface_ipv4 "$_dtn")" ]; then
            _dta=yes
            if ! command -v ping >/dev/null 2>&1; then _dtp=skipped
            elif ping -c 3 -W 3 -I "$_dtn" 1.1.1.1 > /dev/null 2>&1; then _dtp=ok
            else _dtp=failed
            fi
        fi
    fi
    if [ "$_dtd" = no ]; then _dtr=no-load
    elif [ "$_dtv" != "$DRIVER" ]; then _dtr=not-used
    elif [ "$_dtp" = ok ] || [ "$_dtp" = skipped ]; then _dtr=works
    elif [ "$_dtc" = 1 ]; then _dtr=no-internet
    else _dtr=no-link
    fi
    {
        grep -E '^(kernel|chip|adapter|folder|file|sha|boot|started)=' "$DRVTEST_FILE" 2>/dev/null
        echo "state=done"
        echo "result=$_dtr"
        echo "loaded=$_dtd"
        [ -n "$_dte" ] && echo "insmod=$(echo "$_dte" | head -n 1)"
        echo "iface=$_dtn"
        echo "driver=$_dtv"
        echo "carrier=$_dtc"
        echo "speed=$_dts"
        echo "address=$_dta"
        echo "ping=$_dtp"
        # What the kernel said about it, with MAC addresses hidden
        dmesg 2>/dev/null | tail -n +$((_dtl + 1)) | grep -iE 'r8152|usb|eth|cdc|oops|bug|trace' | tail -n 20 \
            | sed 's/\(\([0-9a-fA-F]\{2\}:\)\{3\}\)\([0-9a-fA-F]\{2\}:\)\{2\}[0-9a-fA-F]\{2\}/\1xx:xx:xx/g; s/^/dmesg=/'
    } > "$DRVTEST_FILE.new"
    mv -f "$DRVTEST_FILE.new" "$DRVTEST_FILE"
    sync
    echo "Result: $_dtr"
}

# wait_ipv4 SECONDS: wait for eth0 to have an IPv4 address (webOS's DHCP)
wait_ipv4() {
    _w=0
    while [ "$_w" -lt "$1" ]; do
        [ -n "$(iface_ipv4 eth0)" ] && return 0
        sleep 2
        _w=$((_w + 2))
    done
    [ -n "$(iface_ipv4 eth0)" ]
}

# After standby the adapter comes back on the generic driver, and webOS
# connects it again.  Moving it to the faster driver while webOS is still
# doing that left a C2 showing "no connection" until a reboot.  So: let
# webOS finish first, move the adapter, then make sure webOS reconnected
# it.  If not, take the link down and up so webOS notices it, and if that
# doesn't help either, give the adapter back to the generic driver, which
# was working.  Only checked when eth0 had an address before the move.
takeover_after_standby() {
    _hadip=""
    wait_ipv4 "$NET_SETTLE" && _hadip=1
    take_over
    _sdev=$_dev _sgd=$_gd
    wait_for_nic
    _u=$(find_usb_nic)
    [ -n "$_u" ] && [ "$_u" != eth0 ] && swap_in
    [ -n "$_hadip" ] || return 0
    on_driver "$_sdev" || return 0
    wait_ipv4 "$NET_CHECK" && return 0
    echo "eth0 has no address ${NET_CHECK}s after the move.  Taking the link down and up so webOS sees it again."
    ip link set dev eth0 down
    sleep 2
    ip link set dev eth0 up
    if wait_ipv4 "$NET_CHECK"; then echo "eth0 is connected again."; return 0; fi
    echo "Still no address.  Giving the adapter back to $_sgd, which was working, until the next boot."
    # Re-plugging it in software lets the kernel pick the generic driver,
    # as after standby.  It counts as tried, so it isn't moved again.
    sys_write "$USB_DEVS/$_sdev/authorized" 0
    sleep 2
    sys_write "$USB_DEVS/$_sdev/authorized" 1
    wait_for_nic
    _u=$(find_usb_nic)
    [ -n "$_u" ] && [ "$_u" != eth0 ] && swap_in
    if wait_ipv4 "$NET_CHECK"; then echo "eth0 is connected again, on $_sgd."; else echo "eth0 still has no address.  Rebooting the TV fixes it."; fi
    return 0
}

# Wi-Fi's switch in webOS, through its own connection manager: the same
# switch as in the TV's network settings.  Only --wifi-fallback uses these.
# wifi_status prints enabled, disabled, or nothing when it can't tell.
wifi_status() {
    _ws=$(luna-send -n 1 luna://com.webos.service.wifi/getstatus '{}' 2>/dev/null)
    case "$_ws" in
        *'"serviceDisabled"'*) echo disabled ;;
        *'"returnValue":true'*|*'"returnValue": true'*) echo enabled ;;
    esac
}
wifi_set() {
    case "$(luna-send -n 1 luna://com.webos.service.connectionmanager/setstate "{\"wifi\":\"$1\"}" 2>/dev/null)" in
        *'"returnValue":true'*|*'"returnValue": true'*) return 0 ;;
    esac
    return 1
}

# eth0 has had no cable link for a while: turn Wi-Fi on, but only if it's
# off (if it's on, webOS already uses it).  One try per outage.
wifi_fallback() {
    _wifi_tried=1
    [ "$(wifi_status)" = disabled ] || return 0
    echo "=== $(date) eth0 has had no cable link for ${_down}s: turning Wi-Fi on ==="
    if wifi_set enabled; then
        echo on > "$WIFI_MARK"
        _wifi_on=1
    else
        echo "Could not turn Wi-Fi on."
    fi
}

# The cable works again: turn off the Wi-Fi the fallback turned on.  While
# Wi-Fi is connected, webOS sends traffic over it instead of eth0.
wifi_back() {
    echo "=== $(date) eth0 has its cable link back: turning Wi-Fi off again ==="
    wifi_set disabled || echo "Could not turn Wi-Fi off.  Turn it off in the TV's network settings."
    rm -f "$WIFI_MARK"
    _wifi_on=""
}

# --block-updates: close more of LG's firmware update path, on top of the
# Homebrew Channel's own Block system updates.  It never touches that
# setting, and only adds: webOS's own update switch turned off, every update
# server not already in /etc/hosts (so with the Homebrew Channel's block off,
# its four servers too, in a writable copy of /etc/hosts like the one it
# makes), and one firewall rule for the server the updater reaches by IP.
# All of it is undone by updates_unblock.
UPD_HOSTS="snu.lge.com su.lge.com su-ssl.lge.com su-dev.lge.com snu-dev.lge.com nsu.lge.com ngfts.lge.com"
UPD_IP=156.147.69.32
UPD_TAG="# lg-usb-2-eth0 block-updates"

# webOS's hidden update switch (support/softwareUpdateEnable): true, false,
# or nothing when it can't tell.  With it off, the updater skips its check.
upd_setting() {
    luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings \
        '{"category":"support","keys":["softwareUpdateEnable"]}' 2>/dev/null |
        sed -nE 's/.*"softwareUpdateEnable":[[:space:]]*"?(true|false)"?.*/\1/p'
}
upd_set() {
    case "$(luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
        "{\"category\":\"support\",\"settings\":{\"softwareUpdateEnable\":\"$1\"}}" 2>/dev/null)" in
        *'"returnValue":true'*|*'"returnValue": true'*) return 0 ;;
    esac
    return 1
}
upd_fw_rule() { iptables -C OUTPUT -d "$UPD_IP" -j DROP 2>/dev/null; }
# The update servers missing from /etc/hosts
upd_missing_hosts() {
    for _h in $UPD_HOSTS; do
        grep -Eq "^[^#]*[[:space:]]$_h([[:space:]]|#|$)" "$HOSTS_FILE" 2>/dev/null || printf '%s ' "$_h"
    done
}

updates_block() {
    _us=$(upd_setting)
    # Remember what it was, once, so turning the option off restores it
    [ -n "$_us" ] && [ ! -f "$UPD_MARK" ] && echo "$_us" > "$UPD_MARK"
    if [ "$_us" != false ]; then
        if upd_set false; then echo "Turned webOS's update check off."; else echo "Could not turn webOS's update check off."; fi
    fi
    # An update that was already found or downloaded
    rm -f "$SWUPDATE_DIR/Image_Update_Info.xml" "$SWUPDATE_DIR/Package_Update_Info.xml" 2>/dev/null
    _miss=$(upd_missing_hosts)
    if [ -n "$_miss" ]; then
        # /etc/hosts is read-only unless something (like the Homebrew
        # Channel's own block) put a writable copy over it.  Then do the same.
        if ! ( : >> "$HOSTS_FILE" ) 2>/dev/null; then
            cp "$HOSTS_FILE" "$RUN_DIR/lg-usb-2-eth0.hosts" 2>/dev/null &&
                mount --bind "$RUN_DIR/lg-usb-2-eth0.hosts" "$HOSTS_FILE" 2>/dev/null
        fi
        if ( : >> "$HOSTS_FILE" ) 2>/dev/null; then
            {
                echo "$UPD_TAG"
                for _h in $_miss; do printf '0.0.0.0\t%s %s\n::\t%s %s\n' "$_h" "$UPD_TAG" "$_h" "$UPD_TAG"; done
            } >> "$HOSTS_FILE"
            echo "Blocked update servers in $HOSTS_FILE: $_miss"
            [ -e "${LGU2E_ROOT}/var/luna/preferences/webosbrew_block_updates" ] ||
                echo "The Homebrew Channel's Block system updates is off, so its servers are blocked here too."
        else
            echo "Could not add update servers to $HOSTS_FILE."
        fi
    fi
    if command -v iptables >/dev/null 2>&1 && ! upd_fw_rule; then
        if iptables -I OUTPUT -d "$UPD_IP" -j DROP 2>/dev/null; then echo "Blocked $UPD_IP, which the updater reaches by IP."; else echo "Could not block $UPD_IP."; fi
    fi
    return 0
}

updates_unblock() {
    if [ -f "$UPD_MARK" ]; then
        _was=$(cat "$UPD_MARK" 2>/dev/null)
        [ "$_was" = true ] && { upd_set true || echo "Could not turn webOS's update check back on."; }
        rm -f "$UPD_MARK"
    fi
    if grep -q "$UPD_TAG" "$HOSTS_FILE" 2>/dev/null; then
        # Written in place: /etc/hosts may be a bind mount that can't be replaced
        grep -v "$UPD_TAG" "$HOSTS_FILE" > "$RUN_DIR/lg-usb-2-eth0.hosts.new" 2>/dev/null &&
            cat "$RUN_DIR/lg-usb-2-eth0.hosts.new" > "$HOSTS_FILE" 2>/dev/null
        rm -f "$RUN_DIR/lg-usb-2-eth0.hosts.new"
    fi
    if command -v iptables >/dev/null 2>&1; then
        while upd_fw_rule; do iptables -D OUTPUT -d "$UPD_IP" -j DROP 2>/dev/null || break; done
    fi
    return 0
}

# Runs after boot when --watch or --wifi-fallback is on, or when a --module
# driver is in use.  With a driver: if the adapter comes back on cdc_ncm (TV
# standby can reset USB), move it over again.  With --watch: also follow
# plug and unplug.  With --wifi-fallback: Wi-Fi as a backup for the cable.
watch_run() {
    if [ "$WATCH" = 1 ]; then
        echo "Watching for the adapter (every ${WATCH_EVERY}s)."
    elif [ -n "$DRIVER" ]; then
        echo "Keeping the adapter on $DRIVER (checking every ${WATCH_EVERY}s)."
    fi
    if [ "$WIFI_FALLBACK" = 1 ]; then
        echo "Turning Wi-Fi on if eth0 has no cable link for ${WIFI_GRACE}s."
    fi
    _skip=""
    _last=""
    _down=0
    _up=0
    _wifi_tried=""
    _wifi_on=""
    [ -f "$WIFI_MARK" ] && _wifi_on=1
    while :; do
        sleep "$WATCH_EVERY"
        # Wi-Fi fallback: the cable link is one sysfs read, no subprocess
        if [ "$WIFI_FALLBACK" = 1 ]; then
            _car=""
            { read -r _car < "$NET/eth0/carrier"; } 2>/dev/null
            if [ "$_car" = 1 ]; then
                _down=0
                _wifi_tried=""
                if [ -n "$_wifi_on" ]; then
                    _up=$((_up + WATCH_EVERY))
                    if [ "$_up" -ge "$WIFI_BACK_SECS" ]; then wifi_back; fi
                fi
            else
                _up=0
                _down=$((_down + WATCH_EVERY))
                if [ "$_down" -ge "$WIFI_GRACE" ] && [ -z "$_wifi_tried" ] && [ -z "$_wifi_on" ]; then wifi_fallback; fi
            fi
        fi
        # Cheap checks first, with no subprocesses: is anything bound to
        # cdc_ncm or cdc_ether, and did the list of network interfaces change? Only then
        # look closer. This keeps each check to well under a millisecond.
        _cdc=0
        for _f in "$USB_DRIVERS"/cdc_ncm/*:* "$USB_DRIVERS"/cdc_ether/*:*; do [ -e "$_f" ] && { _cdc=1; break; }; done
        _now=""
        for _p in "$NET"/*; do _now="$_now ${_p##*/}"; done
        _changed=0
        [ "$_now" != "$_last" ] && _changed=1
        _last=$_now
        if [ -n "$DRIVER" ] && [ "$_cdc" = 1 ] && takeover_pending; then
            echo "=== $(date) adapter is on a generic driver again ==="
            takeover_after_standby
            continue
        fi
        [ "$WATCH" = 1 ] || continue
        # Plugging or unplugging adds or removes an interface. A swap that
        # failed is retried only when something changes.
        [ "$_changed" = 1 ] || continue
        _u=$(find_usb_nic)
        if [ -n "$_u" ] && [ "$_u" != eth0 ]; then
            # Don't retry a swap that already failed until something changes
            [ "$_u" = "$_skip" ] && continue
            echo "=== $(date) adapter $_u appeared ==="
            sleep "$SETTLE_SECS"
            take_over
            wait_for_nic
            swap_in || _skip=$(find_usb_nic)
        elif [ -z "$_u" ] && [ ! -e "$NET/eth0" ] && [ -n "$(find_builtin_nic)" ]; then
            echo "=== $(date) adapter gone ==="
            swap_out
            _skip=""
        else
            _skip=""
        fi
    done
}

# What the boot hook does: wait for the adapter, then swap. The hook runs
# this in the background, so it never holds up the Homebrew Channel startup,
# and it changes nothing when no adapter shows up.
boot_run() {
    echo "=== $(date) boot hook (wait ${WAIT_SECS}s${PIN_MAC:+, MAC $PIN_MAC}${MODULE:+, module $MODULE}) ==="
    [ "$BLOCK_UPDATES" = 1 ] && updates_block
    load_module
    _t=0
    while [ "$_t" -lt "$WAIT_SECS" ] && [ -z "$(find_usb_nic)" ]; do
        sleep 2
        _t=$((_t + 2))
    done
    if [ -n "$(find_usb_nic)" ]; then
        # Give a freshly attached adapter a moment to settle
        sleep "$SETTLE_SECS"
        take_over
        wait_for_nic
        swap_in
    else
        echo "No USB Ethernet adapter after ${WAIT_SECS}s. Leaving the built-in port as eth0."
    fi
    if [ "$WATCH" = 1 ] || [ -n "$DRIVER" ] || [ "$WIFI_FALLBACK" = 1 ]; then watch_run; fi
    return 0
}
CORE_EOF
)
eval "$CORE"

# === TV details ===
# Value of "key": "value" in a small JSON file or text (no jq on the TV)
json_get() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${2:--}" 2>/dev/null | head -n 1
}

# Run a command with a time limit when busybox timeout is there
limited() {
    if command -v timeout >/dev/null 2>&1; then timeout 5 "$@"; else "$@"; fi
}

# Fills TV_MODEL, WEBOS_RELEASE, WEBOS_NAME, FIRMWARE
tv_info() {
    [ -n "$TV_INFO_DONE" ] && return 0
    TV_INFO_DONE=1
    WEBOS_RELEASE=$(json_get webos_release "$OS_INFO")
    FIRMWARE=$(json_get webos_manufacturing_version "$OS_INFO")
    [ -n "$WEBOS_RELEASE" ] || WEBOS_RELEASE=$(limited nyx-cmd OSInfo query webos_release 2>/dev/null)
    [ -n "$WEBOS_RELEASE" ] || WEBOS_RELEASE=$(sed -n 's/^VERSION_ID=//p' "${LGU2E_ROOT}/etc/os-release" 2>/dev/null | tr -d '"')
    TV_MODEL=""
    if command -v luna-send >/dev/null 2>&1; then
        INFO=$(limited luna-send -n 1 -f luna://com.webos.service.tv.systemproperty/getSystemInfo \
            '{"keys":["modelName","firmwareVersion"]}' 2>/dev/null)
        TV_MODEL=$(echo "$INFO" | json_get modelName)
        [ -n "$FIRMWARE" ] || FIRMWARE=$(echo "$INFO" | json_get firmwareVersion)
    fi
    # LG's marketing names: 7.x is webOS 22, 8.x webOS 23, 9.x webOS 24, 10.x webOS 25
    case "$WEBOS_RELEASE" in
        [1-6].*) WEBOS_NAME="webOS ${WEBOS_RELEASE%%.*}" ;;
        [7-9].*|1[0-9].*) WEBOS_NAME="webOS $((${WEBOS_RELEASE%%.*} + 15))" ;;
        *) WEBOS_NAME="webOS" ;;
    esac
}

print_tv() {
    tv_info
    echo "Model:     ${TV_MODEL:-unknown}"
    echo "webOS:     $WEBOS_NAME (${WEBOS_RELEASE:-unknown}), firmware ${FIRMWARE:-unknown}"
    echo "Kernel:    $(uname -m), $(uname -r)"
}

hbc_present() { [ -d "${LGU2E_ROOT}/var/lib/webosbrew" ] || [ -d "$HBC_DIR" ]; }

# Everything this script needs before it changes anything
preflight() {
    [ -n "$LGU2E_ROOT" ] || [ "$(id -u)" = 0 ] || error_exit "Run this as root on the TV (it needs a rooted TV)."
    [ -r "$OS_INFO" ] || command -v luna-send >/dev/null 2>&1 || \
        warn "This does not look like webOS. Carrying on, but check you're on the TV."
    command -v ip >/dev/null 2>&1 || error_exit "The 'ip' command is missing, so interfaces can't be renamed."
    ip link show >/dev/null 2>&1 || error_exit "'ip link' does not work here."
    [ -d "$NET" ] || error_exit "$NET is missing, so network devices can't be checked."
}

# === Driver modules ===
# The name a .ko file registers as, read from its modinfo (no modinfo on TVs)
module_name() {
    tr -c '[:alnum:]_=.-' '\n' < "$1" 2>/dev/null | sed -n 's/^name=//p' | head -n 1
}

# Fill DRIVER from MODULE, and check both
resolve_driver() {
    [ -n "$MODULE" ] || return 0
    [ -r "$MODULE" ] || error_exit "Module file $MODULE does not exist."
    if [ -z "$DRIVER" ]; then
        DRIVER=$(module_name "$MODULE")
        [ -n "$DRIVER" ] || { DRIVER=${MODULE##*/}; DRIVER=${DRIVER%.ko}; }
    fi
    case "$DRIVER" in ''|*[!A-Za-z0-9_]*) error_exit "Could not work out the driver name of $MODULE." ;; esac
    _vm=$(module_kernel "$MODULE")
    if ! module_fits "$MODULE"; then
        error_exit "$MODULE is built for kernel $_vm, but this TV runs $(uname -r). Loading it could crash the TV."
    fi
    MODULE_SHA=""
    command -v sha256sum >/dev/null 2>&1 && MODULE_SHA=$(sha256sum "$MODULE" | awk '{print $1}')
    return 0
}

# For apply: use the installed hook's module unless one was given
use_hook_driver() {
    _saved_sha=""
    if [ "$SET_MODULE" = 0 ] && [ "$(hook_state)" = enabled ]; then
        MODULE=$(hook_setting MODULE)
        DRIVER=$(hook_setting DRIVER)
        _saved_sha=$(hook_setting MODULE_SHA)
    fi
    if [ "$SET_MAC" = 0 ] && [ "$(hook_state)" = enabled ]; then PIN_MAC=$(hook_setting PIN_MAC); fi
    if [ "$SET_RTK" = 0 ]; then _v=$(hook_setting REALTEK_MODE); [ -n "$_v" ] && REALTEK_MODE=$_v; fi
    [ -n "$MODULE" ] || return 0
    resolve_driver
    # Check against the checksum saved at install, not the file as it is now
    [ -n "$_saved_sha" ] && MODULE_SHA=$_saved_sha
    return 0
}

# pick_driver KERNEL: of the known drivers for KERNEL, the one that supports
# the adapter plugged in now, or else the first
pick_driver() {
    _pl=$(known_driver "$1") || return 1
    _pf="" _pk=""
    while IFS= read -r _pline; do
        [ -n "$_pline" ] || continue
        [ -n "$_pf" ] || _pf=$_pline
        # shellcheck disable=SC2086 # split the fields on purpose
        set -- $_pline
        if supported_adapter "$5" >/dev/null; then _pk=$_pline; break; fi
    done <<EOF
$_pl
EOF
    echo "${_pk:-$_pf}"
}

# adapter_id NAME: the vid:pid of a USB network interface
adapter_id() { echo "$(sysval "$NET/$1/device/../idVendor"):$(sysval "$NET/$1/device/../idProduct")"; }

# supported_adapter IDS: the vid:pid of a plugged-in adapter that's in the
# comma-separated IDS, whether or not the kernel gave it a driver yet (on
# TVs where LG removed the Realtek driver, it may have none at all)
supported_adapter() {
    _sa=$(find_usb_nic)
    if [ -n "$_sa" ]; then
        _sid=$(adapter_id "$_sa")
        case ",$1," in *",$_sid,"*) echo "$_sid"; return 0 ;; esac
    fi
    for _u in "$USB_DEVS"/*; do
        [ -r "$_u/idVendor" ] || continue
        _sid="$(sysval "$_u/idVendor"):$(sysval "$_u/idProduct")"
        case ",$1," in *",$_sid,"*) echo "$_sid"; return 0 ;; esac
    done
    return 1
}

# Download over HTTPS only. TLS protects the download, but the pinned SHA-256
# is what decides whether the file is kept, so a proxy, an old certificate
# store or busybox wget (which may not check certificates) can't slip a
# different file through. They can only make the download fail.
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --connect-timeout 20 --max-time 300 --retry 2 -o "$1" "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -O "$1" "$2"
    else
        echo "Neither curl nor wget is available."
        return 1
    fi
}

# Certificates can't be checked with a clock that's years off, which happens
# right after boot before the TV syncs its time
clock_ok() {
    _y=$(date +%Y 2>/dev/null)
    case "$_y" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_y" -ge 2025 ]
}

download_help() {
    echo "If the download keeps failing:"
    echo "  - Check the TV is online and its clock is right (it says: $(date))."
    echo "  - Older firmware can have an out-of-date certificate store. Download the file on"
    echo "    your computer instead, copy it to the TV (for example with scp), then run:"
    echo "      sh $0 get-driver --file /path/to/$1"
    echo "    The file is checked against the same SHA-256 either way."
}

get_driver() {
    preflight
    _k=$(uname -r)
    _kd=$(pick_driver "$_k") || {
        info "No known better driver for kernel $_k."
        echo "If someone has built one for this exact kernel, install it with --module /full/path/driver.ko."
        return 0
    }
    # shellcheck disable=SC2086 # split the fields on purpose
    set -- $_kd
    _url=$1 _sum=$2 _file=$3 _page=$4 _ids=$5 _mirror=${6:-}
    _dest="$DRIVER_DIR/$_file"
    info "Kernel $_k has a known better driver: $_file"
    echo "  Built and published by: $_page"
    echo "  Download: $_url"
    [ -n "$_mirror" ] && echo "  Mirror, if that fails: $_mirror"
    echo "  It's a kernel module from that project, not from LG-USB-2-ETH0. It's only offered"
    echo "  for this exact kernel, and its SHA-256 is checked before it's kept."
    if _gid=$(supported_adapter "$_ids"); then
        echo "  It supports your adapter ($_gid)."
    elif [ -n "$(find_usb_nic)" ]; then
        warn "It doesn't support your adapter ($(adapter_id "$(find_usb_nic)")), so it wouldn't help with this one."
    fi
    command -v sha256sum >/dev/null 2>&1 || error_exit "sha256sum is missing, so the download can't be checked. Nothing changed."
    if [ -f "$_dest" ] && [ "$(sha256sum "$_dest" | awk '{print $1}')" = "$_sum" ]; then
        success "Already downloaded and verified: $_dest"
    else
        mkdir -p "$DRIVER_DIR" || error_exit "Could not create $DRIVER_DIR."
        if [ -n "$DRIVER_FILE" ]; then
            [ -r "$DRIVER_FILE" ] || error_exit "Can't read $DRIVER_FILE."
            cp -f "$DRIVER_FILE" "$_dest.part" || error_exit "Could not copy $DRIVER_FILE."
        else
            confirm "Download it?" || { echo "Cancelled. Nothing changed."; return 1; }
            clock_ok || warn "The TV's clock says $(date). Certificates can't be checked until it's right, so the download may fail."
            # The author's copy first, then the mirror if that download fails
            # or isn't the right file.  The checksum below decides either way.
            _gotit=0
            for _u in "$_url" $_mirror; do
                [ "$_u" = "$_url" ] || echo "  Trying the mirror: $_u"
                if fetch "$_dest.part" "$_u" && [ "$(sha256sum "$_dest.part" | awk '{print $1}')" = "$_sum" ]; then
                    _gotit=1; break
                fi
            done
            if [ "$_gotit" = 0 ] && [ ! -s "$_dest.part" ]; then
                rm -f "$_dest.part"
                download_help "$_file"
                error_exit "Download failed. Nothing changed."
            fi
        fi
        _got=$(sha256sum "$_dest.part" | awk '{print $1}')
        if [ "$_got" != "$_sum" ]; then
            rm -f "$_dest.part"
            error_exit "Checksum mismatch (got $_got, expected $_sum). The file was deleted and nothing changed."
        fi
        _vm=$(module_kernel "$_dest.part")
        if ! module_fits "$_dest.part"; then
            rm -f "$_dest.part"
            error_exit "The module is built for kernel $_vm, not $_k. The file was deleted and nothing changed."
        fi
        mv -f "$_dest.part" "$_dest" || error_exit "Could not save $_dest."
        success "Verified and saved: $_dest"
    fi
    echo "Install it with:"
    echo "  sh $0 install --module $_dest"
}

# Where the faster-driver option stands, so it's only offered when it fits:
#   active       a --module driver is set up and passes its checks
#   wrong-kernel set up, but built for another kernel (after a firmware update)
#   changed      set up, but the file changed since install
#   missing      set up, but the file is gone
#   available    not set up; a driver is known for this exact kernel and the
#                adapter plugged in now is one it can run
#   none         nothing to offer: no known driver for this kernel, or no
#                adapter, or an adapter the driver isn't for
driver_offer() {
    _om=$(hook_setting MODULE)
    if [ -n "$_om" ]; then
        [ -r "$_om" ] || { echo missing; return; }
        module_fits "$_om" || { echo wrong-kernel; return; }
        _os=$(hook_setting MODULE_SHA)
        if [ -n "$_os" ] && command -v sha256sum >/dev/null 2>&1 && [ "$(sha256sum "$_om" | awk '{print $1}')" != "$_os" ]; then
            echo changed; return
        fi
        echo active; return
    fi
    _okd=$(pick_driver "$(uname -r)") || { echo none; return; }
    # Only when the module supports a plugged-in adapter
    # shellcheck disable=SC2086 # split the fields on purpose
    set -- $_okd
    if supported_adapter "$5" >/dev/null; then echo available; else echo none; fi
}

# === Testing new drivers ===
# The adapters each kind of experimental driver supports (from their
# aliases): Realtek's r8152 v2.22.1 as DonZoomik patched it (r8152_oot, the
# same as his), and the kernel's own r8152 and ax88179_178a of 4.4 kernels
R8152_IDS="045e:07ab,045e:07c6,04e8:a101,0955:09ff,0bda:8050,0bda:8152,0bda:8153,13b1:0041,17ef:304f,17ef:3062,17ef:3069,17ef:7205,17ef:720c,17ef:7214,2357:0601"
AX88179_IDS="04e8:a100,0b95:178a,0b95:1790,0df6:0072,17ef:304b,2001:4a00"
R8152_OOT_IDS="045e:07ab,045e:07c6,045e:0927,045e:0c5e,04e8:a101,0955:09ff,0b05:1976,0b05:1d91,0bda:8050,0bda:8053,0bda:8152,0bda:8153,0bda:8155,0bda:8156,0bda:8157,0bda:815a,13b1:0041,17ef:304f,17ef:3052,17ef:3054,17ef:3057,17ef:3062,17ef:3069,17ef:3082,17ef:3098,17ef:7205,17ef:720a,17ef:720b,17ef:720c,17ef:7214,17ef:721e,17ef:8153,17ef:a359,17ef:a387,2357:0601,2baf:0012"

# The untested drivers, one per line: kernel, chip ("-" for any), file and
# SHA-256.  A chip-specific one is in <kernel>-<chip> in the mirror's
# experimental folder, others in <kernel>.  One kernel name can run on
# several chips with different configs, so most are built per chip.
# Drivers built here that a tester has reported working, in the same
# "kernel chip file sha256" form as EXPERIMENTAL_DRIVERS below and from the
# same mirror commit.  get-driver offers them like any other known driver.
# scripts/drivers.py promote moves a row here from a driver test report.
TESTED_DRIVERS=""

EXPERIMENTAL_DRIVERS="5.4.268-329.ptl4tv.2 - r8152_oot.ko 450d1655b507c61a50cc94640926c727bd528bfb4bbd0e2b277f7e50c0ad81a9
5.4.268-320 - r8152_oot.ko 952bb6b87b7889d4f6d197133d86ed16630d79c1c56c2f96ad89a51f4c4028f0
5.4.96-307 - r8152_oot.ko 8cbc4e1472de11d3720c36180e717a6dd95ca5d7875fb813febde6af44d927da
5.4.268-294.24.papikonda.2 k24 r8152_oot.ko cd06aaa0cd54da1de85e1e70568f2521aa539e3fc7695e85361c4524cb758da6
4.4.84-612.40.jimna.1 k6lp r8152.ko 388d01ae3d8d58ca7eb82e161bd5675e9d9f2be490a02c2f5c86c42be94edd8e
4.4.84-612.40.jimna.1 k6lp ax88179_178a.ko 0e915333f96c755a292fbfe828ed689421661c46096b12ee897121c317631b22
4.4.84-612.21.6.jardine.2 k6lp r8152.ko f4c84da8cf2cf24ec50daede4ff82f36112d745e59a3d3eef65de9a5edbc7c87
4.4.84-612.21.6.jardine.2 k6lp ax88179_178a.ko 727f2f59e7ab271b88febbde1c9fca5492d0e2c6b106723563daff6ecb2397f3
5.4.268-294.24.papikonda.2 k24n r8152_oot.ko 9d9a23b5c2384c9ec93c78a750f1b33e8ca73120f2dca9d826d0b77f274baeda
5.4.268-294.24.papikonda.2 k25lp r8152_oot.ko 31921857e73f83d8958d0d8afb79d4ee8a555128edd294e233fb96997c3decae
5.4.268-294.24.papikonda.2 k8hp r8152_oot.ko 6b771e9b1abe20dabff4278a0ce290f788d8498a9b39a4d954fc43fcf5570730
5.4.268-294.24.papikonda.2 k8hpp r8152_oot.ko f5612354712de5306fffc85084366d6e5afa97fe05af44c54ae20f9c7c59cdb3
5.4.268-294.24.papikonda.2 k8lpn r8152_oot.ko a995b73fe10ed405824f1e6fd733e8a2df76917f6afad5db9ca39dd612ee232f
5.4.268-294.24.papikonda.2 k8lpn2 r8152_oot.ko c888183287baa0d19befe5a335fb76c5d7fe1bf079eba09905531e2b1672b391
5.4.268-294.ptl4tv.24 k24n r8152_oot.ko 113c7828fea0beb02a7d0d8566bb90491d5b5736537079c2d2b0895db676a3ab
5.4.268-294.ptl4tv.24 k25lp r8152_oot.ko 9b0035c3094381980cb9ffda2b665e310c22ada4ca056a345f2ebf31fdd02d53
5.4.268-294.ptl4tv.24 k25lp ax88179_178a.ko db0902a367c93acde238cf48170cb4c48791ddd748380f8e27b99e645f545c49
5.4.96-115.30.mole.2 k8hp r8152_oot.ko 398b239f2298d00b3dea134eebfa84cee2d79c122f33f68349d923516f1e017c
5.4.96-115.30.mole.2 k8hp ax88179_178a.ko 33e919bd94cec6e3c20921984ba0405a8fd4768d03e41a288ccfe69732e48770
5.4.96-115.30.mole.2 k8lp r8152_oot.ko 2405c5aeded1b052c6ee8f53c7498ac73f38a315788d056cc3eef462577fb801
5.4.96-115.30.mole.2 k8lp ax88179_178a.ko b754497e8c95b7cb377c1b9b6da8fffc70825b68830c3759077ada0a6b7fc385
5.4.96-115.30.mole.2 k8ap r8152_oot.ko 65281484986c73df3f95abe7d2fda7bf7f7e0880c388f32732b34167a8a92b94
5.4.96-115.30.mole.2 k8ap ax88179_178a.ko 6045ef1212973109a33e464f58425770640697cc7c6b838ad708663073d3b852
5.4.96-115.28.mirima.1 k8hp r8152_oot.ko 24eeec6deafe5fb73071732fd1e6bed6de94c5e9a6a877335b830f668829a00d
5.4.96-115.28.mirima.1 k8hp ax88179_178a.ko 5fa2abdd63d67aaaa75cc17ac0fd79264fb7195662e7568bdf617e3c45cdf5d6
5.4.96-115.28.mirima.1 k8lp r8152_oot.ko 12614a7b59b47a74dc53822436059795ed351a247eba0fcb34587c419d3352db
5.4.96-115.28.mirima.1 k8lp ax88179_178a.ko 29db46149c50823ea1810d3955d20c94f195bd3471b9ad4244c44030ed84d11e
5.4.96-115.28.mirima.1 k8ap r8152_oot.ko d097f39b6cad9a093cba010931e99b4af419ac25d15b2d0e9208198534dd848e
5.4.96-115.28.mirima.1 k8ap ax88179_178a.ko b74e8220efe09c51b2d36b2feea7227bab1aa011d30b059e8442260e37f65db7
5.4.268-223.29.okapi.5 k24 r8152_oot.ko 512583cb47eaa2aba21f11425a181753688941e4f1d91f8733172e07483a721c
5.4.268-223.29.okapi.5 k24 ax88179_178a.ko f9d78b081979c205f604113253bede1519e79fb044e7464a4bb71bdc7cd2ddcf
5.4.268-223.29.okapi.5 k8lpn2 r8152_oot.ko 2c8d545fea7b2cf301c93a3070ac1356e63140499524a211217a8f0e7b89a8bf
5.4.268-223.29.okapi.5 k8lpn2 ax88179_178a.ko 5dc25531a00b5f8c0bda28cbadcc8cb2fd7c0781262783ad8d54db14504798bc
5.4.268-223.29.okapi.pine.4 k8hp r8152_oot.ko 116435a955c4121980a020ae695cb6795affa1d72f634de8fc3549fe9f0509cd
5.4.268-223.29.okapi.pine.4 k8hp ax88179_178a.ko d1322d54c8fdfb50c674fcbc8f1312233dfac698ef37bc4b870a5db37e568140
5.4.268-223.29.okapi.pine.4 k8lpn r8152_oot.ko ddffd97ee9436742be876b232f36d53ce051c9c0b2342491a865336193474885
5.4.268-223.29.okapi.pine.4 k8lpn ax88179_178a.ko 9397d0cfe3ba60a50d89a4164fc81b0d76a9a110174d45fabcd743e555ec03b8
5.4.268-223.obr4tv.42 k8hpt r8152_oot.ko 70b6b3f00f1659f33d8cebea170e10d23f67847fbce8750832132f0e18ced407
5.4.268-223.obr4tv.42 k8hpt ax88179_178a.ko 464c8ab0381f2a02eecaf49b2a6318ab9f81c052ccbb8513de8654b7c6b14028
5.4.268-223.29.okapi.pine.4 k8hpp r8152_oot.ko 1f60160b502a51f7fdbf1347dc975f7ca68bd5d580336b56a8a23b175205d244
5.4.268-223.29.okapi.pine.4 k8hpp ax88179_178a.ko 42e7c03cee10cb0cece885806176cda8a6c2382e7487bae02dd1325135911b9e
5.4.268-223.42.okapi.nmrm.2 k24t r8152_oot.ko b4d92c085389e0da84ec8261bd12767c64dde2035ac6c12b7e1dc982224f1ba0
5.4.268-223.42.okapi.nmrm.2 k24t ax88179_178a.ko 1f17eb1cf7895edfe1743b14ad38374290cedaa247bad33963cd211035d992c8
5.4.96-115.16.mebbin.1 k8lp r8152_oot.ko 2551ed3d73a2a96106ab6256f50059a9f3a00691803589434c13526e9b35294f
5.4.96-115.16.mebbin.1 k8lp ax88179_178a.ko 4a3bc86a2c1335dcf2849ea9d216d423e2dcbf2d4ccefb865b10003c0c967ebb
5.4.96-115.16.mebbin.2 k8lp r8152_oot.ko 6746efadc3b19dd2a970aa5be002e72136860c10c0ced0423b28e56686233de7
5.4.96-115.16.mebbin.2 k8lp ax88179_178a.ko 365a58e4f3985ed47eb8323e68c1b6d137525a113834d8862a9d6185acecaaee
5.4.96-115.22.meru.2 k8hpt r8152_oot.ko 85483420c645c546cef952101254911409a813aec1b7b3701b5b13a5da421ea9
5.4.96-115.22.meru.2 k8hpt ax88179_178a.ko 60756f6439644a6eaca3566c8d11b10355b78a7c837239c2bd41b204444c2094
5.4.96-115.22.meru.2 k8lp r8152_oot.ko 7ca7a20d8fa214e1fba824e18f75d28a67192a43d3f00813c52b44700fc27c99
5.4.96-115.22.meru.2 k8lp ax88179_178a.ko 76d2ae8749b8c5ecaf0849d5f65414fe897996342f2960ce804d37c29615606b
5.4.96-115.28.1.22.mirima.2 k8ap r8152_oot.ko 01e46f3241637977fe2c7539199b81b224a006631d572059b9b38b52714876ee
5.4.96-115.28.1.22.mirima.2 k8ap ax88179_178a.ko 90ef60771f0e328675a3c36e8445d9eaa8e9ea9522744d45f63fbe79b73c3820
5.4.96-115.9.marine.1 k8lp r8152_oot.ko 127a548bb76d831c094375b6463d28d81f371a51155227119ebb7ee45d62a5ce
5.4.96-115.9.marine.1 k8lp ax88179_178a.ko 10db7625621ead798282fd3ba45d9afa9fb9baf6d558160af4e50871a5499b78
5.4.96-132.40.nameri.2 k8hpp r8152_oot.ko 154147119ccf6f431e93581c7f9f15b635fc62603b2cfd1f69a4dde53a836112
5.4.96-132.40.nameri.2 k8hpp ax88179_178a.ko ceeeea4cac5d9e3301fe9bcf88ca4b22c6c52a908d7cabe1d9f74d14e528bde7
5.4.96-132.40.nameri.2 k8lpn r8152_oot.ko caa832f4e4baeab1ed1e28988d4b1229e3b292305145d292335869b493c3e158
5.4.96-132.40.nameri.2 k8lpn ax88179_178a.ko 5f974eb43b9b30e59378943dc2f90fe6750b2523293f8da49188bc7e0e3df76e
5.4.96-132.40.nameri.pine.1 k8hp r8152_oot.ko 1025328c8e302b29d18e5c10f1e207bdb61a76267223057c67f647eb4653d82b
5.4.96-132.40.nameri.pine.1 k8hp ax88179_178a.ko 403e0e6de1cda42d6bea552178e07a063eb0360957adc76fc2163e038b02b68f
5.4.96-132.50.namtok.2 k8hpp r8152_oot.ko 142319ec9bf7d1d9ac9c2d296f2908b364eeb538d706e3e6b80a9a3ec4bcad0e
5.4.96-132.50.namtok.2 k8hpp ax88179_178a.ko 66a1b88da655443ebb103caa9f4d639e5e18ccc87e1070f343627fe2625b1b64
5.4.96-132.50.namtok.2 k8lpn r8152_oot.ko 3d4eaddec0bfb8951d174db5c359d31ade8a04bc1f7be9007d38990f48858bd4
5.4.96-132.50.namtok.2 k8lpn ax88179_178a.ko da018ad3fa00e31a9514ab4f684ff628a6ca02f9107fd59fa342cbfc855fe217
5.4.96-223.29.1.okapi.2 k24 r8152_oot.ko 6b4a954a30f722540f52af1d5785bbc5092ee4d694f084a63c099b50ce142050
5.4.96-223.29.1.okapi.2 k24 ax88179_178a.ko ce4dcf5d1260deea17f92eb79c9b8bccf32726e76b0c90ffb8753e3f40b7e020
5.4.96-223.9.oeta.2 k24 r8152_oot.ko aabcb5cd3da9222940916b0f85922937dc3c3a28e9ebe41c646e12a723bb802f
5.4.96-223.9.oeta.2 k24 ax88179_178a.ko 92d973078eb9021e6368d2957a169e397ea3bee10eab803d6fafd3d74aca5e64
5.4.96-223.9.oeta.2 k8lpn2 r8152_oot.ko 332888813780ceb254dca62972185c69f6c55b94282e58876fc9c355d80ce472
5.4.96-223.9.oeta.2 k8lpn2 ax88179_178a.ko 84b3c6a1cf9a24939da08bc4bb782b9e7a734dde4ff3a2f41e0710188f0b1e9f
5.4.96-223.obr4tv.29 k24 r8152_oot.ko 952c2545a8a688981d16ed9f7865721d9a92e30b1d7e8a90f198eb46a4983c89
5.4.96-223.obr4tv.29 k24 ax88179_178a.ko 22a568c650178e9d8812dc65c4a7e8dc88c6311591fa2fbce8c368534d9ed6b6
4.4.84-612.40.jimna.1 k6hp r8152.ko 2502594b536faf6f62a6a89ad618e7d30d43bdcfa9970499196e1bcfcf8b231e
4.4.84-612.40.jimna.1 k6hp ax88179_178a.ko 2bdda8cd0e9ba5dc4a8a8f82266d6695a71a9cb994e82f77a334e6e496253c84
4.4.84-612.21.6.jardine.2 k6hp r8152.ko dd36ef69cf25345c225452aa311b8133dccd502990ef0a58fc3851c4920d21d3
4.4.84-612.21.6.jardine.2 k6hp ax88179_178a.ko bf0167932f63ec376d64174d8b4fb7698fc07eef95cf1f19ca9acec9252ad2da
4.4.84-611.japoon.14 k6lp r8152.ko bd7b248ceea3045f2b60074b5cb2a9906cd41ab9b5f4c6ccc2817e0e427a90f7
4.4.84-611.japoon.14 k6lp ax88179_178a.ko d86d63ae16110ba23867142af62c968a69f3e9230845aeefceb2ae1c325a631c
5.4.268-294.15.paparoa.3 k24n r8152_oot.ko 842d39bae1ec00ddea3dd07d0fefd79af64b5040da551c5a0c5bd3be86d0aa2d
5.4.268-294.15.paparoa.3 k24n ax88179_178a.ko 273bff897780480cc1d3cf4c0ec52c2c07b59a83eebd98ff1ad8409b4d075d90
5.4.268-294.15.paparoa.4 k24n r8152_oot.ko e1b94bccd19f11801e5a68249da96fae0b0bb8d8615e77320235dd7b8e9ccba2
5.4.268-294.15.paparoa.4 k24n ax88179_178a.ko 4bd531cbf8a2a48b6b3395b02c92c1aebebed77d67223e36faa7ca6f146f30cc
5.4.268-294.15.paparoa.4 k25lp r8152_oot.ko 097fd4e6765bd1847d6ba0ed730055d323a5685a856929d67106d5a6fb4501d5
5.4.268-294.15.paparoa.4 k25lp ax88179_178a.ko 85eed149283b7fa70e3f5275a374b51122d5d5fe8bd4169d9202af85b7a5f330
5.4.268-294.17.paparoa.pine.2 k24 r8152_oot.ko e5c0c13999390c28cfc6def5029dc5c1fa22bf770e91bda48efac70d8a3689d6
5.4.268-294.17.paparoa.pine.2 k24 ax88179_178a.ko 222c6eebe72a765838e6d707d26f8ab3ab4d203f012e2355d24e83eff99505c9
5.4.268-294.17.paparoa.pine.2 k8hp r8152_oot.ko 17f217cefd9cb059e8def04ec855fe6856338761eedd13753357ef893615d899
5.4.268-294.17.paparoa.pine.2 k8hp ax88179_178a.ko 30b0d9a6327d6d3b8b878c4ac5ec82834710797215a4445753351d1adf26ebee
5.4.268-294.17.paparoa.pine.2 k8hpp r8152_oot.ko 4ffee4fcc9a436a4085973b16aa5f66fff5728bcdbf2183d43ba2f35920179a6
5.4.268-294.17.paparoa.pine.2 k8hpp ax88179_178a.ko 1ac221993f50e758c8c522f558769c5fac573f06dfe8a4072b860e0b8b53ad8d
5.4.268-294.17.paparoa.pine.2 k8lpn r8152_oot.ko 5afb498b290f7f4eea032b9e855a43f6d4ba499463cc6deb8557170f79a827b8
5.4.268-294.17.paparoa.pine.2 k8lpn ax88179_178a.ko 38c186338c538b05532fa7c6c59c401798932507b29f3cbb2588d5746e3cf63e
5.4.268-294.17.paparoa.pine.2 k8lpn2 r8152_oot.ko 85f6c51cc43cc590c19b877fac35b05150a1c31f0e98b1f2f1de81089f0371ae
5.4.268-294.17.paparoa.pine.2 k8lpn2 ax88179_178a.ko 056959c684d80e008056f46fe4403271fa414815f16438785ecdd2c67c4ae431
4.4.84-612.40.jimna.1 k6lp r8152_oot.ko c9cba7d0ad937c35ec6d32b9165575cc55522e44a5cef129222ff1c4f9ef03a2
4.4.84-612.40.jimna.1 k6hp r8152_oot.ko 92543de3d18db3a39577ddd82118694e14a51eeed6f85e88e16b62192deb3eba
4.4.84-612.21.6.jardine.2 k6lp r8152_oot.ko 78b6123ade80de24ee125f30d87a92a5a7aff351537cb29ba3e5f7793295849e
4.4.84-612.21.6.jardine.2 k6hp r8152_oot.ko 0b05d12230216382f60458f9b4966b135071ae06de4b8f47802b7447274a2f3b
4.4.84-611.japoon.14 k6lp r8152_oot.ko 79441333217f2abaae3ff8d44eefef20e3638d0f6325172cf7077cfbacdac0fa
4.4.84-612.jcl4tv.40 k6lp r8152.ko 90bb0e88c56b405e730af673c9309a215eaea6ce4ce888fbd3c71285f9e47717
4.4.84-612.jcl4tv.40 k6lp r8152_oot.ko 8df6d54ced5d6486449310efe16dfa5e89ad28cbd6d1e479c442b15174d665d3"

# experimental_driver KERNEL: "url sha256 file folder ids" lines for the
# untested drivers built for exactly that kernel (and this TV's chip)
experimental_driver() {
    if [ -n "${LGU2E_TEST_EXPERIMENTAL:-}" ]; then
        echo "$LGU2E_TEST_EXPERIMENTAL"
        return 0
    fi
    driver_rows "$1" "$EXPERIMENTAL_DRIVERS"
}

# tested_driver KERNEL: the drivers built here that a tester reported
# working, for that kernel (and this TV's chip), as known_driver lines
tested_driver() {
    _tt=${LGU2E_TEST_TESTED:-$TESTED_DRIVERS}
    [ -n "$_tt" ] || return 0
    driver_rows "$1" "$_tt" | while read -r _tu _ts _tf _tfo _ti; do
        echo "$_tu $_ts $_tf https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/$_tfo $_ti $_tu"
    done
    return 0
}

# driver_rows KERNEL TABLE: "url sha256 file folder ids" for the rows of a
# "kernel chip file sha256" table that are for KERNEL and this TV's chip
driver_rows() {
    _xo="" _xc="" _xcr=0
    while read -r _xk _xch _xfile _xs; do
        [ "$_xk" = "$1" ] || continue
        _xf=$1
        if [ "$_xch" != - ]; then
            [ "$_xcr" = 1 ] || { _xc=$(tv_soc); _xcr=1; }
            [ "$_xc" = "$_xch" ] || continue
            _xf=$1-$_xch
        fi
        case "$_xfile" in
            r8152_oot.ko) _xi=$R8152_OOT_IDS ;;
            r8152.ko) _xi=$R8152_IDS ;;
            *) _xi=$AX88179_IDS ;;
        esac
        _xo="$_xo$EXPERIMENTAL_URL/$_xf/$_xfile $_xs $_xfile $_xf $_xi
"
    done <<EOF
$2
EOF
    [ -n "$_xo" ] || return 1
    printf '%s' "$_xo"
}

# pick_experimental KERNEL: of its experimental drivers, the one for the
# adapter plugged in (nothing, and false, if none supports it)
pick_experimental() {
    _pel=$(experimental_driver "$1") || return 1
    while IFS= read -r _pe; do
        [ -n "$_pe" ] || continue
        # shellcheck disable=SC2086 # split the fields on purpose
        set -- $_pe
        if supported_adapter "$5" > /dev/null; then echo "$_pe"; return 0; fi
    done <<EOF
$_pel
EOF
    return 1
}

# The adapters a driver file is for, in words
drv_adapters() {
    case "$1" in
        r8152_oot.ko) echo "Realtek RTL8152, RTL8153 or RTL8156" ;;
        r8152.ko) echo "Realtek RTL8152 or RTL8153" ;;
        ax88179_178a.ko) echo "ASIX AX88179" ;;
        *) echo "${1%.ko}" ;;
    esac
}

boot_id() {
    if [ -n "${LGU2E_BOOT_ID:-}" ]; then echo "$LGU2E_BOOT_ID"; else cat /proc/sys/kernel/random/boot_id 2>/dev/null; fi
}
drvtest_get() { sed -n "s/^$1=//p" "$DRVTEST_FILE" 2>/dev/null | head -n 1; }

# A test still marked running from before the last restart never finished:
# the driver most likely froze or crashed the TV.  Record that.
drvtest_settle() {
    [ "$(drvtest_get state)" = running ] || return 0
    [ "$(drvtest_get boot)" != "$(boot_id)" ] || return 0
    { grep -E '^(kernel|chip|adapter|folder|file|sha|boot|started)=' "$DRVTEST_FILE"; echo "state=done"; echo "result=crashed"; } \
        > "$DRVTEST_FILE.new" && mv -f "$DRVTEST_FILE.new" "$DRVTEST_FILE"
}

drvtest_says() {
    case "$1" in
        works) echo "it works: the adapter is on the new driver and online" ;;
        no-internet) echo "the adapter is on the new driver with a cable link, but didn't get online" ;;
        no-link) echo "the adapter is on the new driver, but has no cable link" ;;
        not-used) echo "the driver loaded, but the adapter didn't move to it" ;;
        no-load) echo "the kernel refused to load the driver" ;;
        crashed) echo "the TV froze or restarted during the test" ;;
        *) echo "$1" ;;
    esac
}

# The report to send: no MAC or IP addresses
drvtest_report() {
    tv_info
    _r=$(drvtest_get result)
    echo '```'
    echo "LG-USB-2-ETH0 v$VERSION driver test"
    echo "Model:    ${TV_MODEL:-unknown}"
    echo "Firmware: ${FIRMWARE:-unknown} ($WEBOS_NAME)"
    echo "Kernel:   $(drvtest_get kernel)"
    echo "Chip:     $(drvtest_get chip)"
    echo "Driver:   experimental/$(drvtest_get folder)/$(drvtest_get file) ($(drvtest_get sha | cut -c1-16))"
    echo "Adapter:  $(drvtest_get adapter)"
    echo "Result:   $_r"
    if [ "$_r" != crashed ]; then
        _ri=$(drvtest_get insmod)
        echo "Loaded:   $(drvtest_get loaded)${_ri:+ ($_ri)}"
        _dls=$(drvtest_get speed)
        case "$_dls" in ''|-1|*[!0-9]*) _dls=unknown ;; *) _dls="${_dls}M" ;; esac
        echo "After:    $(drvtest_get iface) on $(drvtest_get driver), carrier $(drvtest_get carrier), link $_dls, address $(drvtest_get address), ping $(drvtest_get ping)"
        if grep -q '^dmesg=' "$DRVTEST_FILE" 2>/dev/null; then
            echo "Kernel log:"
            sed -n 's/^dmesg=/  /p' "$DRVTEST_FILE"
        fi
    fi
    echo '```'
}

drvtest_show() {
    info "Driver test: $(drvtest_says "$(drvtest_get result)")."
    echo "Please send the report below, whatever the result: it's how a driver gets"
    echo "added for this kernel.  Paste it into a driver test report:"
    echo "  $DRVTEST_FORM"
    echo "or reply in https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/4"
    echo
    drvtest_report
}

test_driver() {
    preflight
    drvtest_settle
    if [ "$LAST" = 1 ]; then
        if [ -f "$DRVTEST_FILE" ]; then drvtest_show; else info "No driver test yet."; fi
        return 0
    fi
    [ "$(drvtest_get state)" != running ] || error_exit "A driver test is still running.  Wait a minute, then run 'test-driver --last'."
    _k=$(uname -r)
    _soc=$(tv_soc)
    if [ "$(drvtest_get result)" = crashed ]; then
        warn "The last driver test didn't finish: the TV restarted during it, so the driver most likely froze or crashed it."
        drvtest_show
        confirm "Try it once more?" || return 0
    fi
    _x=$(experimental_driver "$_k") || {
        info "No new driver to test for kernel $_k${_soc:+ ($_soc chip)} yet."
        pick_driver "$_k" > /dev/null && echo "It does have a tested one: run get-driver, or use Faster driver in the app."
        echo "The ones being tested: https://github.com/ohmybahgosh/LG-USB-2-ETH0/blob/main/docs/driver-build.md"
        return 0
    }
    # A tested driver for the adapter plugged in wins
    if [ "$(driver_offer)" = available ]; then
        info "Kernel $_k has a tested driver for your adapter.  Use get-driver, or Faster driver in the app."
        return 0
    fi
    [ -z "$(hook_setting MODULE)" ] || error_exit "A driver module is already set up ($(hook_setting MODULE)).  Turn it off first (install --no-module), restart the TV, then test."
    _xp=$(pick_experimental "$_k") || {
        _xfor=""
        while IFS= read -r _xl; do
            [ -n "$_xl" ] || continue
            # shellcheck disable=SC2086 # split the fields on purpose
            set -- $_xl
            _xfor="${_xfor:+$_xfor, or }$(drv_adapters "$3")"
        done <<EOF
$_x
EOF
        # A kernel with both Realtek builds: name the adapters once
        case "$_xfor" in
            *RTL8156*) _xfor=$(echo "$_xfor" | sed 's/Realtek RTL8152 or RTL8153, or //; s/, or Realtek RTL8152 or RTL8153//') ;;
        esac
        error_exit "Plug in a USB adapter with a chip the new driver is for first: $_xfor."
    }
    # shellcheck disable=SC2086 # split the fields on purpose
    set -- $_xp
    _xurl=$1 _xsum=$2 _xfile=$3 _xfold=$4 _xids=$5
    _xid=$(supported_adapter "$_xids")
    _xchip=$(known_nic_id "$_xid") || _xchip=""
    info "There's a new driver to test for kernel $_k: ${_xfile%.ko}, built from LG's own kernel source."
    echo "It hasn't run on a TV with this kernel yet.  The test:"
    echo "  1. downloads it and checks its SHA-256, and that it's built for exactly this kernel"
    echo "  2. loads it until the next restart only: nothing loads it at boot"
    echo "  3. moves your adapter ($_xid${_xchip:+, $_xchip}) to it and checks it gets online"
    echo "  4. shows a short report to send, so it can be offered to everyone with this kernel"
    warn "If it doesn't fit, the TV can freeze or restart.  Restart it (unplug it if it doesn't restart on its own), then run test-driver again to report that too.  Nothing loads the driver again by itself."
    confirm "Run the test?" || { echo "Cancelled.  Nothing changed."; return 1; }
    command -v sha256sum >/dev/null 2>&1 || error_exit "sha256sum is missing, so the download can't be checked.  Nothing changed."
    mkdir -p "$RUN_DIR" || error_exit "Could not create $RUN_DIR."
    # In RAM: it's gone after a restart, like the test
    _xko="$RUN_DIR/lg-usb-2-eth0-test-$_xfile"
    clock_ok || warn "The TV's clock says $(date).  Certificates can't be checked until it's right, so the download may fail."
    if ! fetch "$_xko.part" "$_xurl"; then
        rm -f "$_xko.part"
        error_exit "Download failed.  Check the TV is online and its clock is right ($(date)).  Nothing changed."
    fi
    _got=$(sha256sum "$_xko.part" | awk '{print $1}')
    if [ "$_got" != "$_xsum" ]; then
        rm -f "$_xko.part"
        error_exit "Checksum mismatch (got $_got, expected $_xsum).  The file was deleted and nothing changed."
    fi
    if [ "$(module_kernel "$_xko.part")" != "$_k" ]; then
        rm -f "$_xko.part"
        error_exit "The module isn't built for kernel $_k.  The file was deleted and nothing changed."
    fi
    mv -f "$_xko.part" "$_xko" || error_exit "Could not save $_xko."
    success "Downloaded and verified."
    { echo "state=running"; echo "boot=$(boot_id)"; echo "kernel=$_k"; echo "chip=${_soc:-unknown}"
      echo "adapter=$_xid${_xchip:+ ($_xchip)}"; echo "folder=$_xfold"; echo "file=$_xfile"; echo "sha=$_xsum"; echo "started=$(date)"; } > "$DRVTEST_FILE"
    sync
    # The driver name the module registers, like r8152_oot
    _xname=$(module_name "$_xko")
    MODULE=$_xko DRIVER=${_xname:-${_xfile%.ko}} MODULE_SHA=$_xsum
    # If the adapter is eth0 now, make it eth0 again after the move
    _xswap=0
    [ "$(find_usb_nic)" = eth0 ] && _xswap=1
    run_detached "DRVTEST_FILE=\"$DRVTEST_FILE\"; DRVTEST_SWAP=$_xswap; drv_try" || { rm -f "$DRVTEST_FILE"; return 1; }
    # The TV app follows it through status --json instead
    [ "$NO_WAIT" = 1 ] && return 0
    _i=0
    while [ "$(drvtest_get state)" = running ] && [ "$_i" -lt 90 ]; do sleep 1; _i=$((_i + 1)); done
    if [ "$(drvtest_get state)" = running ]; then
        warn "Still testing in the background.  Run 'test-driver --last' in a minute for the result."
        return 0
    fi
    echo
    drvtest_show
}

# === Hook state ===
# enabled   the hook runs at boot (a symlink to this script, or a 2.0-2.2 copy)
# broken    the hook is a symlink to a script that's gone (an app was removed)
# legacy    a v1 hook, which renames eth0 even with no adapter
# legacy-disabled, disabled, none
hook_state() {
    if [ -L "$HOOK" ]; then
        if [ -r "$HOOK" ]; then echo enabled; else echo broken; fi
    elif [ -f "$HOOK" ]; then
        if grep -q "$MARKER" "$HOOK" 2>/dev/null; then echo enabled; else echo legacy; fi
    elif [ -f "$OLD_DISABLED_HOOK" ]; then
        echo legacy-disabled
    elif [ -e "$DISABLED_HOOK" ] || [ -L "$DISABLED_HOOK" ]; then
        echo disabled
    else
        echo none
    fi
}

# Stop the boot hook's background job (it only stays around with --watch, or
# while it is still waiting for the adapter). Checks the PID is really the hook.
stop_watcher() {
    [ -r "$PID_FILE" ] || return 0
    _pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) rm -f "$PID_FILE"; return 0 ;; esac
    if kill -0 "$_pid" 2>/dev/null && tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | grep -q 'S01fix-eth'; then
        kill "$_pid" 2>/dev/null && info "Stopped the hook's background job (PID $_pid)."
    fi
    rm -f "$PID_FILE"
}

watcher_pid() {
    _pid=$(cat "$PID_FILE" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_pid" 2>/dev/null && echo "$_pid"
}

# A saved setting: from the settings file, or from a 2.0-2.2 hook that kept
# its settings inside itself
hook_setting() {
    for _f in "$CONF" "$HOOK" "$DISABLED_HOOK"; do
        if [ ! -f "$_f" ] || [ -L "$_f" ]; then continue; fi
        grep -q "^$1=" "$_f" 2>/dev/null || continue
        sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$_f" 2>/dev/null | head -n 1
        return 0
    done
}

# Check settings before they're used as root, wherever they came from
settings_ok() {
    case "$WAIT_SECS" in ''|*[!0-9]*) return 1 ;; esac
    case "$WATCH" in 0|1) ;; *) return 1 ;; esac
    case "$WIFI_FALLBACK" in 0|1) ;; *) return 1 ;; esac
    case "$BLOCK_UPDATES" in 0|1) ;; *) return 1 ;; esac
    case "$REALTEK_MODE" in 0|1) ;; *) return 1 ;; esac
    case "$PARK_NAME" in eth[0-9]) ;; *) return 1 ;; esac
    case "$MODULE" in ''|/*.ko) ;; *) return 1 ;; esac
    case "$MODULE" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
    case "$DRIVER" in *[!A-Za-z0-9_]*) return 1 ;; esac
    case "$MODULE_SHA" in *[!0-9a-f]*) return 1 ;; esac
    [ -z "$PIN_MAC" ] || echo "$PIN_MAC" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1
    return 0
}

# Load saved settings into the variables, except ones given on the command line
load_settings() {
    if [ "$SET_MAC" = 0 ]; then PIN_MAC=$(hook_setting PIN_MAC); fi
    if [ "$SET_WAIT" = 0 ]; then _v=$(hook_setting WAIT_SECS); [ -n "$_v" ] && WAIT_SECS=$_v; fi
    if [ "$SET_MODULE" = 0 ]; then MODULE=$(hook_setting MODULE); DRIVER=$(hook_setting DRIVER); MODULE_SHA=$(hook_setting MODULE_SHA); fi
    if [ "$SET_WATCH" = 0 ]; then _v=$(hook_setting WATCH); [ -n "$_v" ] && WATCH=$_v; fi
    if [ "$SET_WIFI" = 0 ]; then _v=$(hook_setting WIFI_FALLBACK); [ -n "$_v" ] && WIFI_FALLBACK=$_v; fi
    if [ "$SET_BLOCK" = 0 ]; then _v=$(hook_setting BLOCK_UPDATES); [ -n "$_v" ] && BLOCK_UPDATES=$_v; fi
    if [ "$SET_RTK" = 0 ]; then _v=$(hook_setting REALTEK_MODE); [ -n "$_v" ] && REALTEK_MODE=$_v; fi
    _v=$(hook_setting PARK_NAME); [ -n "$_v" ] && PARK_NAME=$_v
    return 0
}

# Absolute path of this script
self_path() {
    case "$0" in /*) _sp=$0 ;; *) _sp="$(pwd)/$0" ;; esac
    readlink -f "$_sp" 2>/dev/null || echo "$_sp"
}

# What the boot hook links to. Inside the TV app, the app's own copy. Otherwise
# a copy in /home/root/lg-usb-2-eth0, so the hook doesn't point at /tmp.
hook_target() {
    _self=$(self_path)
    case "$_self" in
        */usr/palm/applications/*)
            # run-parts skips files that aren't executable. If the app's copy
            # can't be made executable, fall back to a copy in /home/root.
            [ -x "$_self" ] || chmod 755 "$_self" 2>/dev/null
            if [ -x "$_self" ]; then echo "$_self"; return 0; fi ;;
    esac
    _dst="$SCRIPT_HOME/LG-USB-2-ETH0.sh"
    if [ "$_self" != "$(readlink -f "$_dst" 2>/dev/null)" ]; then
        mkdir -p "$SCRIPT_HOME" || return 1
        { cp -f "$_self" "$_dst.new" && chmod 755 "$_dst.new" && mv -f "$_dst.new" "$_dst"; } || return 1
    fi
    echo "$_dst"
}

# Save the settings, then point the boot hook at this script. The Homebrew
# Channel's rules want startup scripts symlinked, not copied, so an updated
# script (or app) is picked up without reinstalling the hook.
write_hook() {
    mkdir -p "$INIT_DIR" "${CONF%/*}" || error_exit "Could not create $INIT_DIR."
    {
        echo "# $MARKER v$VERSION. Change it with: sh LG-USB-2-ETH0.sh install [options]"
        echo "PIN_MAC=\"$PIN_MAC\""
        echo "WAIT_SECS=\"$WAIT_SECS\""
        echo "PARK_NAME=\"$PARK_NAME\""
        echo "MODULE=\"$MODULE\""
        echo "DRIVER=\"$DRIVER\""
        echo "MODULE_SHA=\"$MODULE_SHA\""
        echo "WATCH=\"$WATCH\""
        echo "WIFI_FALLBACK=\"$WIFI_FALLBACK\""
        echo "BLOCK_UPDATES=\"$BLOCK_UPDATES\""
        echo "REALTEK_MODE=\"$REALTEK_MODE\""
    } > "$CONF.new" || error_exit "Could not write $CONF."
    mv -f "$CONF.new" "$CONF" || error_exit "Could not write $CONF."
    _target=$(hook_target) || error_exit "Could not put a copy of the script in $SCRIPT_HOME."
    { ln -sfn "$_target" "$HOOK.new" && mv -f "$HOOK.new" "$HOOK"; } || error_exit "Could not install $HOOK."
    rm -f "$DISABLED_HOOK" "$OLD_DISABLED_HOOK"
}

# Run by the Homebrew Channel at boot, through the S01fix-eth symlink. Starts
# the background job and returns at once. Does nothing without valid settings.
boot_main() {
    PATH=$PATH:/usr/sbin:/usr/bin:/sbin:/bin
    [ -f "$CONF" ] || exit 0
    load_settings
    mkdir -p "$RUN_DIR" "${LOG_FILE%/*}" 2>/dev/null
    if ! settings_ok; then
        echo "=== $(date) boot hook: $CONF has invalid settings, so nothing was changed ===" >> "$LOG_FILE"
        exit 0
    fi
    # Keep the log small
    [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 32768 ] && mv -f "$LOG_FILE" "$LOG_FILE.1"
    ( boot_run ) >> "$LOG_FILE" 2>&1 < /dev/null &
    echo $! > "$PID_FILE"
    exit 0
}

# === Live changes ===
# Interface the current SSH session comes in on, if we can tell
session_iface() {
    _ip=$(echo "$SSH_CONNECTION" | awk '{print $3}')
    [ -n "$_ip" ] || return 0
    ip -o -4 addr show 2>/dev/null | awk -v ip="$_ip" '{split($4, a, "/"); if (a[1] == ip) {print $2; exit}}'
}

# Renaming takes interfaces down, which drops a session that uses them. So the
# change runs detached from this session and finishes even if we get cut off.
run_detached() {
    _what=$1
    _sess=$(session_iface)
    _usb=$(find_usb_nic)
    _bi=$(find_builtin_nic)
    if [ -n "$_sess" ] && { [ "$_sess" = "$_usb" ] || [ "$_sess" = "$_bi" ]; }; then
        warn "You're connected through $_sess, which is about to be renamed."
        echo "Your session will drop for a moment. The change still finishes on the TV."
        echo "Reconnect over Wi-Fi (or the other cable) afterwards. Its IP address may change."
        confirm "Go ahead?" || { echo "Cancelled. Nothing changed."; return 1; }
    elif [ -z "$SSH_CONNECTION" ]; then
        warn "If you're connected over a wired port, this drops your session for a moment."
        echo "The change still finishes on the TV. Wi-Fi is the safe way in."
        confirm "Go ahead?" || { echo "Cancelled. Nothing changed."; return 1; }
    fi
    _job="PIN_MAC=\"$PIN_MAC\"; PARK_NAME=\"$PARK_NAME\"; MODULE=\"$MODULE\"; DRIVER=\"$DRIVER\"; MODULE_SHA=\"$MODULE_SHA\"; REALTEK_MODE=\"$REALTEK_MODE\"
LOG_FILE=\"$LOG_FILE\"; RUN_DIR=\"$RUN_DIR\"
$CORE
$_what"
    _now="$RUN_DIR/lg-usb-2-eth0.now"
    mkdir -p "$RUN_DIR" "${LOG_FILE%/*}" 2>/dev/null
    : > "$_now"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c "$_job" > "$_now" 2>&1 < /dev/null &
    else
        nohup sh -c "$_job" > "$_now" 2>&1 < /dev/null &
    fi
    _pid=$!
    _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 20 ]; do
        sleep 1
        _i=$((_i + 1))
    done
    cat "$_now" 2>/dev/null
    if kill -0 "$_pid" 2>/dev/null; then
        warn "Still working in the background. Run 'status' in a minute to see how it went."
    fi
    { echo "=== $(date) $_what (by hand) ==="; cat "$_now"; } >> "$LOG_FILE" 2>/dev/null
    return 0
}

# === Commands ===
show_plan() {
    _usb=$(find_usb_nic)
    _bi=$(find_builtin_nic)
    echo
    print_tv
    echo "Built-in:  ${_bi:-not found}"
    if [ -n "$_usb" ]; then
        echo "Adapter:   $_usb, driver $(nic_driver "$_usb"), MAC $(nic_mac "$_usb")"
    else
        echo "Adapter:   none visible${PIN_MAC:+ with MAC $PIN_MAC} (unplugged, or no driver for it)"
    fi
    echo
}

install_fix() {
    preflight
    hbc_present || error_exit "Homebrew Channel not found. It runs the boot hook, so install it first."
    load_settings
    settings_ok || error_exit "The saved settings in $CONF aren't valid. Run 'uninstall', then 'install' again."
    resolve_driver
    show_plan
    info "At every boot the hook will:"
    echo "  1. Wait up to ${WAIT_SECS}s in the background for a USB Ethernet adapter${PIN_MAC:+ with MAC $PIN_MAC}"
    [ -n "$MODULE" ] && echo "     (after loading $MODULE, and moving the adapter from cdc_ncm to $DRIVER)"
    [ -z "$MODULE" ] && [ "$REALTEK_MODE" = 1 ] && [ -d "$USB_DRIVERS/r8152" ] && echo "     (switching a Realtek adapter left on the generic driver to its Realtek mode, so the kernel's own r8152 takes it)"
    echo "  2. If one shows up, rename the built-in port to $PARK_NAME and the adapter to eth0"
    echo "  3. If none shows up, change nothing, so the built-in port keeps working"
    [ "$WATCH" = 1 ] && echo "  4. Keep watching: swap the adapter in when it's plugged in, give eth0 back when it's unplugged"
    [ "$WIFI_FALLBACK" = 1 ] && echo "  -  If eth0 loses its cable link for ${WIFI_GRACE}s while Wi-Fi is off, turn Wi-Fi on, and off again once the cable works"
    [ "$BLOCK_UPDATES" = 1 ] && echo "  -  Block firmware updates more thoroughly, on top of the Homebrew Channel's own block (starts now)"
    echo "It writes $CONF and the link $HOOK, and nothing else."
    case "$(hook_state)" in legacy|legacy-disabled)
        warn "This replaces the v1 hook, which renamed eth0 even with no adapter plugged in." ;;
    esac
    [ -z "$(find_usb_nic)" ] && warn "No adapter is visible right now. Run 'status' if it's plugged in."
    if [ -n "$MODULE" ] && { [ -e "$AUTOBIND_HOOK" ] || [ -L "$AUTOBIND_HOOK" ]; }; then
        warn "DonZoomik's r8152-autobind boot hook is installed too ($AUTOBIND_HOOK)."
        echo "  It does the same job as --module. Keep only one: sh /home/root/r8152-autobind.sh uninstall"
    fi
    confirm "Install the boot hook?" || { echo "Cancelled. Nothing changed."; return 1; }
    stop_watcher
    write_hook
    success "Boot hook installed: $HOOK"
    if [ "$BLOCK_UPDATES" = 1 ]; then
        updates_block
    elif [ -f "$UPD_MARK" ] || grep -q "$UPD_TAG" "$HOSTS_FILE" 2>/dev/null; then
        updates_unblock
        echo "Update blocking is off again.  The Homebrew Channel's own block is unchanged."
    fi
    if [ "$APPLY_NOW" = 1 ]; then
        rm -f "$TAKEOVER_STATE"
        run_detached "realtek_mode; wait_for_nic; swap_in"
    else
        echo "It takes effect at the next reboot. Run 'apply' to switch now."
    fi
}

uninstall_fix() {
    preflight
    if [ "$(hook_state)" = none ]; then
        rm -f "$CONF"
        info "No boot hook installed."
    else
        confirm "Remove the boot hook?" || { echo "Cancelled. Nothing changed."; return 1; }
        stop_watcher
        rm -f "$HOOK" "$DISABLED_HOOK" "$OLD_DISABLED_HOOK" "$HOOK.new" "$CONF" || error_exit "Could not remove the hook."
        success "Boot hook removed."
    fi
    if [ -f "$WIFI_MARK" ]; then
        rm -f "$WIFI_MARK"
        warn "The Wi-Fi fallback had turned Wi-Fi on, and it stays on.  Turn it off in the TV's network settings if you don't want it."
    fi
    if [ -f "$UPD_MARK" ] || grep -q "$UPD_TAG" "$HOSTS_FILE" 2>/dev/null; then
        updates_unblock
        echo "Undid --block-updates.  The Homebrew Channel's own Block system updates is unchanged."
    fi
    _bi=$(find_builtin_nic)
    if [ "$APPLY_NOW" = 1 ]; then
        run_detached swap_out
    elif [ -n "$_bi" ] && [ "$_bi" != eth0 ]; then
        echo "The adapter stays eth0 until you reboot or run 'revert'."
    fi
}

disable_fix() {
    case "$(hook_state)" in
        enabled|legacy|broken)
            stop_watcher
            { { [ -L "$HOOK" ] || chmod 644 "$HOOK"; } && mv -f "$HOOK" "$DISABLED_HOOK"; } || error_exit "Could not disable the hook."
            success "Hook disabled. It won't run at boot until you enable it." ;;
        legacy-disabled)
            { chmod 644 "$OLD_DISABLED_HOOK" && mv -f "$OLD_DISABLED_HOOK" "$DISABLED_HOOK"; } || error_exit "Could not move the old hook."
            success "Moved the v1 disabled hook out of init.d, where it could still run at boot." ;;
        disabled) info "The hook is already disabled." ;;
        *) warn "No boot hook installed." ;;
    esac
}

enable_fix() {
    _from=""
    case "$(hook_state)" in
        disabled) _from=$DISABLED_HOOK ;;
        legacy-disabled) _from=$OLD_DISABLED_HOOK ;;
        enabled|legacy|broken) info "The hook is already enabled."; return 0 ;;
        *) warn "No boot hook installed. Use 'install'."; return 0 ;;
    esac
    { mv -f "$_from" "$HOOK" && { [ -L "$HOOK" ] || chmod 755 "$HOOK"; }; } || error_exit "Could not enable the hook."
    success "Hook enabled. It runs at the next boot."
    [ -L "$HOOK" ] || grep -q "$MARKER" "$HOOK" || warn "This is the v1 hook. Run 'install' to upgrade it."
}

apply_now() {
    preflight
    use_hook_driver
    if [ -n "$DRIVER" ]; then
        rm -f "$TAKEOVER_STATE"
        run_detached "load_module; take_over; wait_for_nic; swap_in"
    elif [ "$REALTEK_MODE" = 1 ]; then
        rm -f "$TAKEOVER_STATE"
        run_detached "realtek_mode; wait_for_nic; swap_in"
    else
        run_detached swap_in
    fi
}
revert_now() { preflight; run_detached swap_out; }

# Known USB Ethernet chips (vendor:product), to spot an adapter with no driver
known_nic_id() {
    case "$1" in
        0bda:8152) echo "Realtek RTL8152" ;;
        0bda:8153) echo "Realtek RTL8153" ;;
        0bda:8156) echo "Realtek RTL8156" ;;
        0bda:8157) echo "Realtek RTL8157" ;;
        0bda:8050|0bda:8052|0bda:8053|0bda:8151|0bda:8155|0bda:815a) echo "Realtek RTL815x" ;;
        0b95:1790|0b95:178a|0b95:1780) echo "ASIX AX88179/178A" ;;
        0b95:7720|0b95:772a|0b95:772b|0b95:7e2b|0b95:1720|05ac:1402) echo "ASIX AX88772/88172" ;;
        0424:7500|0424:7505|0424:9500|0424:ec00) echo "Microchip/SMSC" ;;
        0424:7800|0424:7801|0424:7850) echo "Microchip LAN78xx" ;;
        2357:0601|2357:0602) echo "TP-Link (Realtek)" ;;
        045e:07ab|045e:07c6|045e:0927|13b1:0041|0b05:1976|17ef:3052|17ef:3054|17ef:3069|17ef:3082|17ef:720c|17ef:7214|17ef:721e|17ef:a387|04e8:a101|0955:09ff) echo "OEM Realtek" ;;
        *) return 1 ;;
    esac
}

speed_label() {
    case "$1" in
        1.5|12) echo "USB 1.1" ;;
        480) echo "USB 2.0" ;;
        5000) echo "USB 3.0" ;;
        10000|20000) echo "USB 3.1+" ;;
        *) echo "USB ${1:-?}" ;;
    esac
}

show_status() {
    ISSUES=0
    ISSUE_LIST=""
    NOTES=""
    echo
    log "$CYAN" "=== LG-USB-2-ETH0 v$VERSION status ==="
    print_tv

    echo
    log "$CYAN" "Boot hook"
    case "$(hook_state)" in
        enabled)
            if [ -L "$HOOK" ]; then
                log "$GREEN" "  Installed and enabled ($HOOK -> $(readlink "$HOOK"))"
            else
                log "$GREEN" "  Installed and enabled ($HOOK)"
                status_note "The hook is a copy from an older version. Run 'install' to switch it to a link (your settings are kept)."
            fi
            _s="  Waits $(hook_setting WAIT_SECS)s"
            [ -n "$(hook_setting PIN_MAC)" ] && _s="$_s, only for MAC $(hook_setting PIN_MAC)"
            [ -n "$(hook_setting MODULE)" ] && _s="$_s, loads $(hook_setting MODULE)"
            [ -n "$(hook_setting DRIVER)" ] && _s="$_s (driver $(hook_setting DRIVER))"
            [ "$(hook_setting WATCH)" = 1 ] && _s="$_s, keeps watching (--watch)"
            [ "$(hook_setting WIFI_FALLBACK)" = 1 ] && _s="$_s, Wi-Fi as a backup (--wifi-fallback)"
            [ "$(hook_setting BLOCK_UPDATES)" = 1 ] && _s="$_s, blocks firmware updates (--block-updates)"
            echo "$_s"
            _w=$(watcher_pid) && echo "  Background job running (PID $_w)" ;;
        legacy)
            log "$YELLOW" "  Old v1 hook installed. It renames eth0 even with no adapter plugged in."
            status_issue "Run 'install' to replace the v1 hook." ;;
        legacy-disabled)
            log "$YELLOW" "  Old v1 hook, \"disabled\" inside init.d ($OLD_DISABLED_HOOK)"
            status_issue "Busybox run-parts may still run that file at boot. Run 'disable' to move it out, or 'install' to upgrade." ;;
        disabled) log "$YELLOW" "  Installed but disabled ($DISABLED_HOOK)" ;;
        broken)
            log "$YELLOW" "  The hook points at a script that's gone ($(readlink "$HOOK"))"
            status_issue "The app or script the boot hook used was removed. Run 'install' to relink it, or 'uninstall'." ;;
        none) echo "  Not installed" ;;
    esac
    hbc_present || status_issue "Homebrew Channel not found, so a boot hook would never run."

    echo
    log "$CYAN" "Network interfaces"
    _usb_seen=0
    _wired_up=0
    for _sp in "$NET"/*; do
        _sn=${_sp##*/}
        [ -e "$_sp/device" ] || continue
        if is_wifi "$_sn"; then _kind="Wi-Fi"
        elif is_usb_nic "$_sn"; then _kind="USB Ethernet"; _usb_seen=1
        elif is_builtin_nic "$_sn"; then _kind="built-in Ethernet"
        else _kind="other"
        fi
        _car=$(sysval "$_sp/carrier" 2>/dev/null)
        _spd=$(sysval "$_sp/speed" 2>/dev/null)
        case "$_spd" in ''|-1|*[!0-9]*) _spd="" ;; esac
        [ "$_car" = 1 ] && [ "$_kind" != "Wi-Fi" ] && _wired_up=$((_wired_up + 1))
        printf '  %-9s %-18s driver %-14s %s\n' "$_sn" "$_kind" "$(nic_driver "$_sn")" "$(nic_mac "$_sn")"
        if [ "$_kind" = "Wi-Fi" ]; then
            if [ "$_car" = 1 ]; then _line="connected"; else _line="not connected"; fi
        elif [ "$_car" = 1 ]; then _line="cable in"
        else _line="no cable"
        fi
        [ -n "$_spd" ] && _line="$_line, link $_spd Mbit/s"
        _ip=$(iface_ipv4 "$_sn")
        _line="$_line, IPv4 ${_ip:-none}"
        if [ "$_kind" = "USB Ethernet" ]; then
            _bus=$(sysval "$_sp/device/../speed")
            _line="$_line, on $(speed_label "$_bus")"
            [ "$_bus" = 12 ] && status_issue "$_sn runs at USB 1.1 speed. Try another port or cable."
            [ "$_bus" = 480 ] && status_note "$_sn is on USB 2.0, which tops out around 300 Mbit/s on these TVs."
            [ "$_car" = 1 ] && [ -z "$_ip" ] && status_note "$_sn has a cable but no IPv4 address yet. webOS may still be setting it up."
            _dup=$(sysval "$_sp/duplex" 2>/dev/null)
            [ "$_dup" = half ] && _line="$_line, half duplex"
            if [ "$_car" = 1 ] && [ -n "$_spd" ] && [ "$_spd" -lt 1000 ]; then
                status_issue "$_sn's cable link is only $_spd Mbit/s, so it's no faster than the built-in port. Usually that's a cable with only two wire pairs (many flat or old cables), a 100 Mbit/s port on the router or switch, or a loose plug. Try a Cat5e or better cable, or another port."
            elif [ "$_car" = 1 ] && [ "$_dup" = half ]; then
                status_issue "$_sn's cable link is half duplex, which is slow and loses packets. Try another cable or another port on the router or switch."
            fi
        fi
        echo "            $_line"
    done
    _def=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
    echo "  Default route: ${_def:-none}"

    # USB adapters the kernel sees but no network driver claimed
    for _u in "$USB_DEVS"/*; do
        [ -r "$_u/idVendor" ] || continue
        _id="$(sysval "$_u/idVendor"):$(sysval "$_u/idProduct")"
        _chip=$(known_nic_id "$_id") || continue
        _has_net=0
        for _i in "$_u"/*:*/net/*; do [ -e "$_i" ] && _has_net=1; done
        if [ "$_has_net" = 0 ]; then
            status_issue "USB adapter $_id ($_chip) is plugged in, but no driver made a network device for it."
            status_note "This kernel ($(uname -r)) seems to lack a driver for that chip. Try an adapter with another chip, or load a module built for this exact kernel with --module."
        fi
    done

    echo
    log "$CYAN" "USB network drivers on this kernel"
    _list=""
    _hd=$(hook_setting DRIVER)
    _seen=""
    # Drivers built into the kernel have no .ko file and often no /sys/module
    # folder, so lsmod never shows them: modules.builtin lists them, and a
    # registered USB driver has a folder under /sys/bus/usb/drivers
    _bif="${LGU2E_ROOT}/lib/modules/$(uname -r)/modules.builtin"
    for _m in r8152 $_hd r8152_oot ax88179_178a asix cdc_ether cdc_ncm smsc95xx lan78xx usbnet; do
        case " $_seen " in *" $_m "*) continue ;; esac
        _seen="$_seen $_m"
        _ko=$(find "${LGU2E_ROOT}/lib/modules/$(uname -r)" -name "$_m.ko*" 2>/dev/null | head -n 1)
        if grep -q "/$_m\.ko\$" "$_bif" 2>/dev/null; then
            _list="$_list $_m(built in)"
        elif [ -d "$SYS_MODULES/$_m" ]; then
            _list="$_list $_m(loaded)"
        elif [ -d "$USB_DRIVERS/$_m" ] && [ -z "$_ko" ]; then
            _list="$_list $_m(built in)"
        elif [ -n "$_ko" ]; then
            _list="$_list $_m(file)"
        fi
    done
    if [ -n "$_list" ]; then echo "  ${_list# }"; else echo "  none found in the kernel, /sys/module or /lib/modules"; fi

    _hm=$(hook_setting MODULE)
    if [ -n "$_hm" ]; then
        if [ ! -r "$_hm" ]; then
            status_issue "The driver module $_hm is missing. Run 'get-driver' and 'install --module' again, or 'install --no-module'."
        else
            _hk=$(module_kernel "$_hm")
            if ! module_fits "$_hm"; then
                status_issue "The driver module is built for kernel $_hk, but the TV now runs $(uname -r), probably after a firmware update. It won't be loaded. Run 'get-driver' to see if there's one for the new kernel."
            fi
            _hs=$(hook_setting MODULE_SHA)
            if [ -n "$_hs" ] && command -v sha256sum >/dev/null 2>&1 && [ "$(sha256sum "$_hm" | awk '{print $1}')" != "$_hs" ]; then
                status_issue "The driver module changed since it was installed, so it won't be loaded. Run 'install' again if you replaced it on purpose."
            fi
        fi
    fi
    _bi=$(find_builtin_nic)
    _usb=$(find_usb_nic)
    _ud=""
    [ -n "$_usb" ] && _ud=$(nic_driver "$_usb")
    case "$_ud" in cdc_ncm|cdc_ether)
        _ui=$(readlink -f "$NET/$_usb/device" 2>/dev/null); _ui=${_ui##*/}; _ui=${_ui%%:*}
        if [ -n "$_hd" ]; then
            status_note "$_usb is still on $_ud, not $_hd. Run 'apply', or check $LOG_FILE."
        elif [ -d "$USB_DRIVERS/r8152" ] && [ "$(sysval "$USB_DEVS/$_ui/idVendor")" = 0bda ] \
            && [ -n "$(sysval "$USB_DEVS/$_ui/bConfigurationValue")" ] && [ "$(sysval "$USB_DEVS/$_ui/bConfigurationValue")" != 1 ]; then
            if [ "$(cut -d' ' -f1 "$REALTEK_STATE" 2>/dev/null)" = failed ]; then
                _rx=""
                if [ "$(driver_offer)" = available ]; then _rx="  A driver is known for this kernel and adapter: run 'get-driver'."
                elif pick_experimental "$(uname -r)" >/dev/null; then _rx="  There's a new driver to test for this kernel: run 'test-driver'."
                fi
                status_note "Realtek mode was tried, but the kernel's r8152 didn't take your adapter, so it's back on the generic $_ud driver.$_rx"
            elif [ "$REALTEK_MODE" = 0 ] || [ "$(hook_setting REALTEK_MODE)" = 0 ]; then
                status_note "This kernel has r8152, but your Realtek adapter is in its standard USB mode, where only the generic $_ud driver can use it.  Realtek mode switches it over: install --realtek-mode, then apply."
            else
                status_note "This kernel has r8152, but your Realtek adapter is in its standard USB mode, where only the generic $_ud driver can use it.  Run 'apply' (or reboot) and Realtek mode switches it over."
            fi
        elif [ "$(driver_offer)" = available ]; then
            status_note "$_usb uses the generic $_ud driver. A better driver is known for this kernel and adapter: run 'get-driver'."
        fi ;;
    esac
    if [ -z "$_usb" ] && [ -z "$_hd" ] && [ "$(driver_offer)" = available ]; then
        status_note "Your adapter has no driver on this TV, but one is known for this kernel and adapter: run 'get-driver'."
    fi
    if { [ -e "$AUTOBIND_HOOK" ] || [ -L "$AUTOBIND_HOOK" ]; }; then
        if [ -n "$_hd" ]; then
            status_issue "DonZoomik's r8152-autobind hook and --module both manage the driver. Keep one: sh /home/root/r8152-autobind.sh uninstall"
        else
            status_note "DonZoomik's r8152-autobind hook is installed. 'install --module' can do the same job inside LG-USB-2-ETH0."
        fi
    fi
    case "$(hook_state)" in
        enabled|legacy|legacy-disabled)
            [ "$_usb_seen" = 0 ] && status_note "The hook is on, but no adapter is visible now, so a boot right now would change nothing." ;;
    esac
    if [ -n "$_usb" ] && [ "$_usb" != eth0 ] && [ "$(hook_state)" = enabled ]; then
        status_note "The adapter is $_usb, not eth0 yet. Reboot, run 'apply', or check $LOG_FILE."
    fi
    if [ "$_usb" = eth0 ] && [ "$(sysval "$NET/eth0/carrier" 2>/dev/null)" = 1 ] && [ -n "$_def" ] && [ "$_def" != eth0 ]; then
        status_note "Traffic goes out $_def, not the adapter. webOS prefers Wi-Fi while it's connected: turn Wi-Fi off in the TV's settings, or unplug and replug the network cable."
    fi
    if [ "$(hook_setting BLOCK_UPDATES)" != 1 ]; then
        if [ -e "${LGU2E_ROOT}/var/luna/preferences/webosbrew_block_updates" ]; then
            status_note "The Homebrew Channel blocks four of LG's update servers, but misses others.  install --block-updates closes the rest."
        else
            status_note "Firmware updates aren't blocked.  An update can remove root for good: install with --block-updates, or turn on Block system updates in the Homebrew Channel."
        fi
    fi
    [ -f "$WIFI_MARK" ] && status_note "The Wi-Fi fallback turned Wi-Fi on because eth0 lost its cable link.  It turns Wi-Fi off again once the cable works for ${WIFI_BACK_SECS}s."
    [ "$_wired_up" -gt 1 ] && status_note "Both wired ports have a cable. Unplug the built-in one, or traffic may take the slower port."
    if [ "$_usb" = eth0 ]; then
        echo
        log "$GREEN" "The USB adapter is eth0${_bi:+ and the built-in port is $_bi}."
    fi

    if [ -s "$LOG_FILE" ]; then
        echo
        log "$CYAN" "Last log lines ($LOG_FILE)"
        tail -n 6 "$LOG_FILE" | sed 's/^/  /'
    fi
    echo
    if [ "$ISSUES" = 0 ]; then log "$GREEN" "No problems found."; else log "$RED" "$ISSUES problem(s) found."; fi
    if [ -n "$NOTES" ]; then
        log "$YELLOW" "Notes:"
        printf '%s\n' "$NOTES" | sed '1d'
    fi
    return 0
}
status_issue() { log "$RED" "  ! $1"; ISSUES=$((ISSUES + 1)); ISSUE_LIST="$ISSUE_LIST
$1"; }
status_note() { NOTES="$NOTES
  - $1"; }

# === JSON status (for the TV app) ===
json_esc() { printf '%s' "$1" | tr -d '\000-\011\013-\037' | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'NR > 1 {printf "\\n"} {printf "%s", $0}'; }
js() { printf '"%s"' "$(json_esc "$1")"; }
jb() { if [ "$1" = 1 ]; then printf true; else printf false; fi; }
# A JSON array from lines, skipping empty ones and the "  - " note prefix
jarr() {
    printf '['
    _first=1
    printf '%s\n' "$1" | while IFS= read -r _l; do
        _l=${_l#  - }
        [ -n "$_l" ] || continue
        [ "$_first" = 1 ] || printf ','
        _first=0
        js "$_l"
    done
    printf ']'
}

# nic_json NAME: one interface as a JSON object, or null
nic_json() {
    if [ -z "$1" ] || [ ! -e "$NET/$1" ]; then printf null; return; fi
    _jp="$NET/$1"
    _jc=$(sysval "$_jp/carrier" 2>/dev/null)
    _js=$(sysval "$_jp/speed" 2>/dev/null)
    case "$_js" in ''|-1|*[!0-9]*) _js=0 ;; esac
    printf '{"name":%s,"driver":%s,"mac":%s,"carrier":%s,"speed":%s,"duplex":%s,"ip":%s' \
        "$(js "$1")" "$(js "$(nic_driver "$1")")" "$(js "$(nic_mac "$1")")" \
        "$(jb "$([ "$_jc" = 1 ] && echo 1)")" "$_js" "$(js "$(sysval "$_jp/duplex" 2>/dev/null)")" "$(js "$(iface_ipv4 "$1")")"
    if is_usb_nic "$1"; then
        _jid="$(sysval "$_jp/device/../idVendor"):$(sysval "$_jp/device/../idProduct")"
        printf ',"id":%s,"chip":%s,"bus":%s' "$(js "$_jid")" "$(js "$(known_nic_id "$_jid")")" \
            "$(js "$(speed_label "$(sysval "$_jp/device/../speed")")")"
    fi
    printf '}'
}

show_json() {
    # Reuse every check from 'status', with its text thrown away
    { show_status; } > /dev/null 2>&1
    tv_info
    _ju=$(find_usb_nic)
    _jbi=$(find_builtin_nic)
    # The main Wi-Fi interface: wlan* first, never a p2p* (Wi-Fi Direct) one
    _jw=""
    for _p in "$NET"/wlan* "$NET"/*; do
        _n=${_p##*/}
        case "$_n" in p2p*) continue ;; esac
        [ -e "$_p" ] && is_wifi "$_n" && { _jw=$_n; break; }
    done
    _jpid=$(watcher_pid) || _jpid=""
    _kd=0; _kf=""; _kp=""
    if _k=$(pick_driver "$(uname -r)"); then
        _kd=1
        # shellcheck disable=SC2086 # split the fields on purpose
        set -- $_k
        _kf="$DRIVER_DIR/$3"
        _kp=$4
    fi
    _ab=0; { [ -e "$AUTOBIND_HOOK" ] || [ -L "$AUTOBIND_HOOK" ]; } && _ab=1
    # The version the last in-app update installed, so the app can show
    # what's new once it opens again
    _jupd=$(sed -n 's/^Updated the app to \([0-9][0-9.]*\)\.$/\1/p' "$LOG_FILE" 2>/dev/null | tail -n 1)
    printf '{"version":%s,"updatedTo":%s,"model":%s,"webos":%s,"webosRelease":%s,"firmware":%s,"kernel":%s,' \
        "$(js "$VERSION")" "$(js "$_jupd")" "$(js "$TV_MODEL")" "$(js "$WEBOS_NAME")" "$(js "$WEBOS_RELEASE")" "$(js "$FIRMWARE")" "$(js "$(uname -r)")"
    printf '"updates":{"check":%s,"hbcBlock":%s,"missingHosts":%s,"firewall":%s},' \
        "$(js "$(upd_setting)")" "$(jb "$([ -e "${LGU2E_ROOT}/var/luna/preferences/webosbrew_block_updates" ] && echo 1)")" \
        "$(js "$(upd_missing_hosts | sed 's/ $//')")" "$(jb "$(command -v iptables >/dev/null 2>&1 && upd_fw_rule && echo 1)")"
    printf '"hook":{"state":%s,"link":%s,"wait":%s,"mac":%s,"module":%s,"driver":%s,"watch":%s,"wifiFallback":%s,"wifiFallbackOn":%s,"blockUpdates":%s,"realtekMode":%s,"running":%s,"pid":%s},' \
        "$(js "$(hook_state)")" "$(js "$(readlink "$HOOK" 2>/dev/null)")" "$(js "$(hook_setting WAIT_SECS)")" \
        "$(js "$(hook_setting PIN_MAC)")" "$(js "$(hook_setting MODULE)")" "$(js "$(hook_setting DRIVER)")" \
        "$(jb "$(hook_setting WATCH)")" "$(jb "$(hook_setting WIFI_FALLBACK)")" "$(jb "$([ -f "$WIFI_MARK" ] && echo 1)")" "$(jb "$(hook_setting BLOCK_UPDATES)")" \
        "$(jb "$([ "$(hook_setting REALTEK_MODE)" != 0 ] && echo 1)")" \
        "$(jb "$([ -n "$_jpid" ] && echo 1)")" "$(js "$_jpid")"
    printf '"realtek":{"r8152":%s,"result":%s},' \
        "$(jb "$([ -d "$USB_DRIVERS/r8152" ] && echo 1)")" "$(js "$(cut -d' ' -f1 "$REALTEK_STATE" 2>/dev/null)")"
    printf '"adapter":%s,"adapterIsEth0":%s,"builtin":%s,"wifi":%s,' \
        "$(nic_json "$_ju")" "$(jb "$([ "$_ju" = eth0 ] && echo 1)")" "$(nic_json "$_jbi")" "$(nic_json "$_jw")"
    printf '"defaultRoute":%s,"knownDriver":%s,"driverOffer":%s,"driverFile":%s,"driverPage":%s,"driverDownloaded":%s,"autobindHook":%s,' \
        "$(js "$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')")" "$(jb "$_kd")" "$(js "$(driver_offer)")" "$(js "$_kf")" "$(js "$_kp")" \
        "$(jb "$([ -n "$_kf" ] && [ -f "$_kf" ] && echo 1)")" "$(jb "$_ab")"
    # A driver to test: only when no tested one fits (or is set up already)
    drvtest_settle
    _xa=0 _xok=0 _xfo=""
    if [ "$(driver_offer)" = none ] && _x=$(experimental_driver "$(uname -r)"); then
        _xa=1
        # shellcheck disable=SC2086 # split the fields on purpose
        set -- $_x
        _xfo=$4
        pick_experimental "$(uname -r)" > /dev/null && _xok=1
    fi
    printf '"driverTest":{"available":%s,"adapterOk":%s,"folder":%s,"state":%s,"result":%s},' \
        "$(jb "$_xa")" "$(jb "$_xok")" "$(js "$_xfo")" "$(js "$(drvtest_get state)")" "$(js "$(drvtest_get result)")"
    if [ -n "$(speed_get down)$(speed_get up)" ]; then
        printf '"speed":{"interface":%s,"server":%s,"pingMs":%s,"downMbps":%s,"upMbps":%s,"at":%s},' \
            "$(js "$(speed_get iface)")" "$(js "$(speed_get server)")" "$(speed_get ping | grep . || echo null)" \
            "$(speed_get down | grep . || echo null)" "$(speed_get up | grep . || echo null)" "$(speed_get at | grep . || echo null)"
    else
        printf '"speed":null,'
    fi
    printf '"issues":%s,"notes":%s,"log":%s}\n' "$(jarr "$ISSUE_LIST")" "$(jarr "$NOTES")" "$(jarr "$(tail -n 8 "$LOG_FILE" 2>/dev/null)")"
}

# Hide the device-specific half of a MAC address in reports
# === Speed test ===
# Cloudflare's speed test endpoints: no account, and the nearest of their
# servers answers.  Several streams at once, for a few seconds each way, like
# speed.cloudflare.com itself.  Each transfer is 25 MB; a worker repeats
# them until its time is up and reports its own rate, and the rates add up.
SPEED_URL=${LGU2E_SPEED_URL:-https://speed.cloudflare.com}
SPEED_SECS=${LGU2E_SPEED_SECS:-6}
SPEED_STREAMS=4
SPEED_CHUNK=25000000
SPEED_FILE="$RUN_DIR/lg-usb-2-eth0.speed"

# speed_worker down|up OUTFILE: write "bytes seconds" for this stream
speed_worker() {
    _se=$(( $(date +%s) + SPEED_SECS ))
    _sb=0; _st=0; _sn=0
    while [ "$_sn" -lt 20 ]; do
        _sl=$(( _se - $(date +%s) ))
        # Always at least one transfer, even if the clock just ticked over
        if [ "$_sl" -le 0 ]; then
            [ "$_sn" = 0 ] || break
            _sl=1
        fi
        if [ "$1" = down ]; then
            _sr=$(curl -s -o /dev/null --max-time "$_sl" -w '%{size_download} %{time_total}' "$SPEED_URL/__down?bytes=$SPEED_CHUNK" 2>/dev/null)
        else
            _sr=$(head -c "$SPEED_CHUNK" /dev/zero | curl -s -o /dev/null --max-time "$_sl" -X POST \
                -H 'Content-Type: application/octet-stream' -T - -w '%{size_upload} %{time_total}' "$SPEED_URL/__up" 2>/dev/null)
        fi
        case "$_sr" in *[0-9]' '[0-9]*) ;; *) break ;; esac
        _sb=$(awk -v a="$_sb" -v b="${_sr% *}" 'BEGIN { printf "%.0f", a + b }')
        _st=$(awk -v a="$_st" -v b="${_sr#* }" 'BEGIN { printf "%.3f", a + b }')
        _sn=$((_sn + 1))
    done
    echo "$_sb $_st" > "$2"
}

# speed_run down|up: Mbit/s over all streams, or nothing if it failed
speed_run() {
    _sp="$RUN_DIR/lg-usb-2-eth0.sp"
    _si=1
    while [ "$_si" -le "$SPEED_STREAMS" ]; do
        speed_worker "$1" "$_sp.$_si" &
        _si=$((_si + 1))
    done
    wait
    cat "$_sp".* 2>/dev/null | awk '$2 > 0 { r += $1 * 8 / $2 / 1000000 } END { if (r > 0) printf "%.0f", r }'
    rm -f "$_sp".*
}

# speed_ping: the fastest of 5 TCP connects, in ms
speed_ping() {
    _pi=0
    while [ "$_pi" -lt 5 ]; do
        curl -s -o /dev/null --max-time 5 -w '%{time_connect} %{time_namelookup}\n' "$SPEED_URL/__down?bytes=0" 2>/dev/null
        _pi=$((_pi + 1))
    done | awk '$1 > 0 { v = ($1 - $2) * 1000; if (m == "" || v < m) m = v } END { if (m != "") printf "%.0f", m }'
}

# speed_set KEY VALUE: remember one result for the report and the app
speed_set() {
    { grep -v "^$1=" "$SPEED_FILE" 2>/dev/null; echo "$1=$2"; } > "$SPEED_FILE.new" && mv -f "$SPEED_FILE.new" "$SPEED_FILE"
}
speed_get() { sed -n "s/^$1=//p" "$SPEED_FILE" 2>/dev/null | head -n 1; }

speed_test() {
    command -v curl >/dev/null 2>&1 || error_exit "The speed test needs curl, and this TV doesn't have it."
    case "$PHASE" in ''|ping|down|up) ;; *) error_exit "--phase is ping, down or up" ;; esac
    _iface=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
    [ -n "$_iface" ] || error_exit "The TV has no internet connection (no default route)."
    _ping=""; _down=""; _up=""; _colo=""
    if [ -z "$PHASE" ] || [ "$PHASE" = ping ]; then
        [ "$JSON" = 1 ] || info "Speed test over $_iface, against Cloudflare.  This uses a few hundred MB of data."
        _colo=$(curl -s -D - -o /dev/null --max-time 10 "$SPEED_URL/__down?bytes=0" 2>/dev/null | tr -d '\r' | sed -n 's/^[Cc]olo: *//p' | head -n 1)
        _ping=$(speed_ping)
        [ -n "$_ping" ] || error_exit "Couldn't reach $SPEED_URL.  Check the TV's internet connection."
        rm -f "$SPEED_FILE"
        speed_set ping "$_ping"; speed_set iface "$_iface"; speed_set server "$_colo"; speed_set at "$(date +%s)"
    fi
    if [ -z "$PHASE" ] || [ "$PHASE" = down ]; then
        _down=$(speed_run down)
        speed_set down "$_down"
    fi
    if [ -z "$PHASE" ] || [ "$PHASE" = up ]; then
        _up=$(speed_run up)
        speed_set up "$_up"
    fi
    if [ "$JSON" = 1 ]; then
        printf '{"interface":%s,"server":%s,"pingMs":%s,"downMbps":%s,"upMbps":%s}\n' \
            "$(js "$_iface")" "$(js "${_colo:-$(speed_get server)}")" "${_ping:-null}" "${_down:-null}" "${_up:-null}"
        return 0
    fi
    _where=Cloudflare
    [ -n "$_colo" ] && _where="Cloudflare $_colo"
    echo "Speed test over $_iface ($_where)"
    [ -n "$_ping" ] && echo "  Latency   $_ping ms"
    if [ -z "$PHASE" ] || [ "$PHASE" = down ]; then echo "  Download  ${_down:-failed} ${_down:+Mbit/s}"; fi
    if [ -z "$PHASE" ] || [ "$PHASE" = up ]; then echo "  Upload    ${_up:-failed} ${_up:+Mbit/s}"; fi
}

# === Updates ===
# The script runs either from inside the TV app or on its own (copied to the
# TV by hand).  The app updates as a whole, by installing the release's IPK
# the same way the Homebrew Channel does.  The plain script replaces itself
# with the release's copy.  Either way the download is checked against the
# release's SHA-256 first.

# app or script
install_kind() {
    case "$(self_path)" in */usr/palm/applications/"$APP_ID"/*) echo app ;; *) echo script ;; esac
}

current_version() {
    _cv=""
    if [ "$(install_kind)" = app ]; then
        _ad=$(self_path); _ad=${_ad%/assets/*}
        _cv=$(json_get version "$_ad/appinfo.json")
    fi
    echo "${_cv:-$VERSION}"
}

# ver_gt A B: A is newer than B (1.2 and 1.2.0 are the same)
ver_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, ".")
        for (i = 1; i <= 3; i++) { p = x[i] + 0; q = y[i] + 0; if (p != q) exit !(p > q) }
        exit 1 }'
}

# Does the Homebrew Channel know our repo?  Then it offers app updates
# itself, and that's the normal way to get them.
from_homebrew() {
    grep -qF "${REPO_URL#https://}" "$HBC_STORAGE"/*.ldb "$HBC_STORAGE"/*.log 2>/dev/null
}

# Fetch the latest release's manifest into LATEST_*; fails quietly
latest_release() {
    _mf="$RUN_DIR/lg-usb-2-eth0.manifest"
    mkdir -p "$RUN_DIR" 2>/dev/null
    fetch "$_mf" "$RELEASES/latest/download/$APP_ID.manifest.json" >/dev/null 2>&1 || { rm -f "$_mf"; return 1; }
    LATEST_VERSION=$(json_get version "$_mf")
    LATEST_IPK=$(json_get ipkUrl "$_mf")
    LATEST_SHA=$(json_get sha256 "$_mf")
    LATEST_SIZE=$(sed -n 's/.*"ipkSize"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$_mf" | head -n 1)
    rm -f "$_mf"
    case "$LATEST_VERSION" in [0-9]*.[0-9]*) ;; *) return 1 ;; esac
    return 0
}

file_sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

update_check() {
    _kind=$(install_kind)
    _cur=$(current_version)
    _src=sideloaded
    from_homebrew && _src=homebrew
    if ! latest_release; then
        if [ "$JSON" = 1 ]; then
            printf '{"current":%s,"latest":null,"newer":false,"kind":%s,"source":%s,"error":%s}\n' \
                "$(js "$_cur")" "$(js "$_kind")" "$(js "$_src")" "$(js "Couldn't check $RELEASES")"
        else
            warn "Couldn't check for updates ($RELEASES).  Is the TV online?"
        fi
        return 1
    fi
    _newer=0
    ver_gt "$LATEST_VERSION" "$_cur" && _newer=1
    if [ "$JSON" = 1 ]; then
        printf '{"current":%s,"latest":%s,"newer":%s,"kind":%s,"source":%s,"notes":%s}\n' \
            "$(js "$_cur")" "$(js "$LATEST_VERSION")" "$(jb "$_newer")" "$(js "$_kind")" "$(js "$_src")" \
            "$(js "$RELEASES/tag/v$LATEST_VERSION")"
        return 0
    fi
    if [ "$_newer" = 1 ]; then
        info "Version $LATEST_VERSION is out (you have $_cur).  What's new: $RELEASES/tag/v$LATEST_VERSION"
        if [ "$_kind" = app ] && [ "$_src" = homebrew ]; then
            echo "The Homebrew Channel will offer it, since you added its repo ($REPO_URL)."
        fi
    else
        success "Up to date ($_cur)."
    fi
    return 0
}

update_now() {
    update_check || return 1
    ver_gt "$LATEST_VERSION" "$(current_version)" || return 0
    command -v sha256sum >/dev/null 2>&1 || error_exit "sha256sum is missing, so the download can't be checked.  Nothing changed."
    confirm "Update to $LATEST_VERSION?" || { echo "Cancelled.  Nothing changed."; return 1; }
    if [ "$(install_kind)" = app ]; then
        update_app
    else
        update_script
    fi
}

# Install the release's IPK.  This replaces the app (and this script inside
# it) and closes the app, so the install runs from a separate job that
# waits for the new version and then opens the app again.
update_app() {
    case "$LATEST_SHA" in *[!0-9a-f]*|'') error_exit "The release has no checksum for the app.  Nothing changed." ;; esac
    case "$LATEST_IPK" in https://*.ipk) ;; *) error_exit "Unexpected download link in the release: $LATEST_IPK" ;; esac
    _ipk="$RUN_DIR/lg-usb-2-eth0-update.ipk"
    info "Downloading $LATEST_IPK"
    fetch "$_ipk.part" "$LATEST_IPK" || { rm -f "$_ipk.part"; error_exit "Download failed.  Nothing changed."; }
    _got=$(file_sha "$_ipk.part")
    if [ "$_got" != "$LATEST_SHA" ]; then
        rm -f "$_ipk.part"
        error_exit "Checksum mismatch (got $_got, expected $LATEST_SHA).  The file was deleted and nothing changed."
    fi
    if [ -n "$LATEST_SIZE" ] && [ "$(wc -c < "$_ipk.part" | tr -d ' ')" != "$LATEST_SIZE" ]; then
        rm -f "$_ipk.part"
        error_exit "The download is the wrong size.  The file was deleted and nothing changed."
    fi
    mv -f "$_ipk.part" "$_ipk"
    _job="i=0
luna-send -n 1 luna://com.webos.appInstallService/dev/install '{\"id\":\"$APP_ID\",\"ipkUrl\":\"$_ipk\"}'
while [ \$i -lt 45 ]; do
    sleep 2
    luna-send -n 1 luna://com.webos.applicationManager/getAppInfo '{\"id\":\"$APP_ID\"}' | grep -q '\"version\": *\"$LATEST_VERSION\"' && break
    i=\$((i + 1))
done
rm -f '$_ipk'
if [ \$i -lt 45 ]; then
    echo 'Updated the app to $LATEST_VERSION.'
    luna-send -n 1 luna://com.webos.applicationManager/launch '{\"id\":\"$APP_ID\"}' >/dev/null
else
    echo 'The app update to $LATEST_VERSION did not finish.  The current version stays installed.'
fi"
    {
        echo "=== $(date) update to $LATEST_VERSION ==="
    } >> "$LOG_FILE" 2>/dev/null
    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c "$_job" >> "$LOG_FILE" 2>&1 < /dev/null &
    else
        nohup sh -c "$_job" >> "$LOG_FILE" 2>&1 < /dev/null &
    fi
    success "Checked the download.  Installing $LATEST_VERSION now: the app closes and opens again by itself."
}

# Replace this script (and the boot hook's copy) with the release's copy
update_script() {
    _self=$(self_path)
    _new="$RUN_DIR/lg-usb-2-eth0-update.sh"
    _sums="$RUN_DIR/lg-usb-2-eth0-update.sums"
    _url="$RELEASES/download/v$LATEST_VERSION"
    info "Downloading $_url/LG-USB-2-ETH0.sh"
    if ! fetch "$_new" "$_url/LG-USB-2-ETH0.sh" || ! fetch "$_sums" "$_url/SHA256SUMS"; then
        rm -f "$_new" "$_sums"
        error_exit "Download failed.  Nothing changed."
    fi
    _want=$(awk '$2 ~ /LG-USB-2-ETH0\.sh$/ {print $1; exit}' "$_sums")
    _got=$(file_sha "$_new")
    rm -f "$_sums"
    if [ -z "$_want" ] || [ "$_got" != "$_want" ]; then
        rm -f "$_new"
        error_exit "Checksum mismatch (got $_got, expected ${_want:-nothing}).  The file was deleted and nothing changed."
    fi
    sh -n "$_new" 2>/dev/null || { rm -f "$_new"; error_exit "The download isn't a valid script.  Nothing changed."; }
    # The boot hook may point at a copy in $SCRIPT_HOME; keep that current too
    _hooked=$(readlink -f "$HOOK" 2>/dev/null)
    for _dst in "$_self" "$_hooked"; do
        if [ -z "$_dst" ] || [ ! -f "$_dst" ]; then continue; fi
        case "$_dst" in */usr/palm/applications/*) continue ;; esac
        { cp -f "$_new" "$_dst.new" && chmod 755 "$_dst.new" && mv -f "$_dst.new" "$_dst"; } \
            || { rm -f "$_new" "$_dst.new"; error_exit "Couldn't write $_dst."; }
    done
    rm -f "$_new"
    success "Updated to $LATEST_VERSION.  Your settings and boot hook are unchanged."
}

# The last speed test as a line for the report, or nothing
speed_summary() {
    _d=$(speed_get down); _u=$(speed_get up)
    [ -n "$_d$_u" ] || return 0
    echo "${_d:-?} down / ${_u:-?} up Mbit/s, $(speed_get ping) ms, over $(speed_get iface) (speedtest)"
}

mask_mac() { echo "$1" | sed 's/^\(..:..:..\):.*/\1:xx:xx:xx/'; }

# Short, paste-ready report for GitHub issues. MAC addresses are masked.
show_report() {
    tv_info
    echo '```'
    echo "LG-USB-2-ETH0 v$VERSION report"
    echo "Model:   ${TV_MODEL:-unknown}"
    echo "webOS:   $WEBOS_NAME (${WEBOS_RELEASE:-unknown}), firmware ${FIRMWARE:-unknown}"
    echo "Kernel:  $(uname -r) ($(uname -m))"
    # The chip, and the USB network drivers built into the kernel (they have
    # no .ko file, so they only show up in modules.builtin)
    _soc=$(tv_soc)
    [ -n "$_soc" ] && echo "Chip:    $_soc"
    _bi=$(grep -E '/net/usb/' "${LGU2E_ROOT}/lib/modules/$(uname -r)/modules.builtin" 2>/dev/null | sed 's#.*/##; s#\.ko$##' | tr '\n' ' ')
    echo "Built in: ${_bi:-unknown}"
    drvtest_settle
    [ -f "$DRVTEST_FILE" ] && echo "Driver test: $(drvtest_get result) (experimental/$(drvtest_get folder))"
    _h=$(hook_state)
    if [ "$_h" = enabled ]; then
        _h="$_h, wait $(hook_setting WAIT_SECS)s"
        [ -n "$(hook_setting PIN_MAC)" ] && _h="$_h, pinned MAC"
        [ -n "$(hook_setting MODULE)" ] && _h="$_h, module $(basename "$(hook_setting MODULE)")"
        [ "$(hook_setting WATCH)" = 1 ] && _h="$_h, watch"
        [ "$(hook_setting WIFI_FALLBACK)" = 1 ] && _h="$_h, wifi-fallback"
        [ "$(hook_setting BLOCK_UPDATES)" = 1 ] && _h="$_h, block-updates"
        [ "$(hook_setting REALTEK_MODE)" = 0 ] && _h="$_h, no-realtek-mode"
    fi
    echo "Hook:    $_h"
    echo "Interfaces:"
    for _rp in "$NET"/*; do
        _rn=${_rp##*/}
        [ -e "$_rp/device" ] || continue
        if is_wifi "$_rn"; then _rk=wifi
        elif is_usb_nic "$_rn"; then _rk=usb
        elif is_builtin_nic "$_rn"; then _rk=builtin
        else _rk=other
        fi
        _rl="  $_rn $_rk driver=$(nic_driver "$_rn") mac=$(mask_mac "$(nic_mac "$_rn")") carrier=$(sysval "$_rp/carrier" 2>/dev/null || echo down)"
        _rs=$(sysval "$_rp/speed" 2>/dev/null)
        case "$_rs" in ''|-1|*[!0-9]*) ;; *) _rl="$_rl link=${_rs}M" ;; esac
        [ "$(sysval "$_rp/duplex" 2>/dev/null)" = half ] && _rl="$_rl half-duplex"
        if [ "$_rk" = usb ]; then
            _rl="$_rl id=$(sysval "$_rp/device/../idVendor"):$(sysval "$_rp/device/../idProduct") bus=$(speed_label "$(sysval "$_rp/device/../speed")")"
        fi
        echo "$_rl"
    done
    for _u in "$USB_DEVS"/*; do
        [ -r "$_u/idVendor" ] || continue
        _id="$(sysval "$_u/idVendor"):$(sysval "$_u/idProduct")"
        _chip=$(known_nic_id "$_id") || continue
        _has_net=0
        for _i in "$_u"/*:*/net/*; do [ -e "$_i" ] && _has_net=1; done
        [ "$_has_net" = 0 ] && echo "  no driver: $_id ($_chip)"
    done
    _list=""
    for _m in r8152 r8152_oot $(hook_setting DRIVER) ax88179_178a asix cdc_ether cdc_ncm smsc95xx lan78xx usbnet; do
        case " $_list " in *" $_m "*) continue ;; esac
        { [ -d "$SYS_MODULES/$_m" ] || [ -d "$USB_DRIVERS/$_m" ]; } && _list="$_list $_m"
    done
    # A driver built into the kernel may have no /sys/module folder (it still
    # has one under /sys/bus/usb/drivers), so also list the ones the USB
    # adapters are using right now.
    for _rp in "$NET"/*; do
        _rn=${_rp##*/}
        is_usb_nic "$_rn" || continue
        _m=$(nic_driver "$_rn")
        [ -n "$_m" ] || continue
        case " $_list " in *" $_m "*) ;; *) _list="$_list $_m" ;; esac
    done
    echo "Drivers loaded:${_list:- none}"
    [ -f "$REALTEK_STATE" ] && echo "Realtek mode: $(cat "$REALTEK_STATE" 2>/dev/null)"
    echo "Default route: $(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
    _sp=$(speed_summary)
    [ -n "$_sp" ] && echo "Speed:   $_sp"
    echo '```'
}

main_menu() {
    if [ ! -t 0 ] && ! ( : < /dev/tty ) 2>/dev/null; then
        usage
        error_exit "No terminal for the menu. Give a command instead, for example 'install -y'."
    fi
    while true; do
        echo
        log "$CYAN" "=== LG-USB-2-ETH0 v$VERSION ==="
        echo "1) Install boot hook"
        echo "2) Uninstall boot hook"
        echo "3) Status and checks"
        echo "4) Swap the adapter in now"
        echo "5) Give eth0 back to the built-in port now"
        echo "6) Disable boot hook"
        echo "7) Enable boot hook"
        echo "8) Report for a GitHub issue"
        echo "s) Speed test"
        echo "u) Check for updates"
        # Only offered when a driver is known for this exact kernel and adapter
        _offer=$(driver_offer)
        case "$_offer" in available) echo "9) Get the faster driver for this TV" ;; esac
        _xoffer=0
        if [ "$_offer" != available ] && experimental_driver "$(uname -r)" > /dev/null; then
            _xoffer=1
            echo "t) Test a new driver for this TV"
        fi
        echo "0) Exit"
        read_answer "Choose an option: " || exit 1
        case "$ANSWER" in
            1) install_fix ;;
            2) uninstall_fix ;;
            3) show_status ;;
            4) apply_now ;;
            5) revert_now ;;
            6) disable_fix ;;
            7) enable_fix ;;
            8) show_report ;;
            s|S) speed_test ;;
            u|U) update_now ;;
            9) if [ "$_offer" = available ]; then get_driver; else echo "Pick one of the numbers shown."; fi ;;
            t|T) if [ "$_xoffer" = 1 ]; then test_driver; else echo "Pick one of the numbers shown."; fi ;;
            0|q|Q) echo "Bye."; exit 0 ;;
            *) echo "Pick one of the numbers shown." ;;
        esac
        read_answer "Press Enter for the menu..." || exit 0
    done
}

# === Arguments ===
# Started by the Homebrew Channel at boot, through the hook symlink
case "${0##*/}" in S01fix-eth) boot_main ;; esac

CMD=""
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --now) APPLY_NOW=1 ;;
        --mac)
            shift
            PIN_MAC=$(echo "$1" | tr 'A-F' 'a-f'); SET_MAC=1
            echo "$PIN_MAC" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || error_exit "--mac needs a MAC like aa:bb:cc:dd:ee:ff" ;;
        --wait)
            shift
            WAIT_SECS=$1; SET_WAIT=1
            case "$WAIT_SECS" in ''|*[!0-9]*) error_exit "--wait needs a number of seconds" ;; esac ;;
        --module)
            shift
            MODULE=$1; SET_MODULE=1
            case "$MODULE" in /*.ko) ;; *) error_exit "--module needs the full path to a .ko file" ;; esac
            # It is written into a root boot script, so only allow plain path characters
            case "$MODULE" in *[!A-Za-z0-9._/-]*) error_exit "--module path may only use letters, digits, '.', '_', '-' and '/'" ;; esac ;;
        --watch) WATCH=1; SET_WATCH=1 ;;
        --no-watch) WATCH=0; SET_WATCH=1 ;;
        --wifi-fallback) WIFI_FALLBACK=1; SET_WIFI=1 ;;
        --no-wifi-fallback) WIFI_FALLBACK=0; SET_WIFI=1 ;;
        --block-updates) BLOCK_UPDATES=1; SET_BLOCK=1 ;;
        --no-block-updates) BLOCK_UPDATES=0; SET_BLOCK=1 ;;
        --realtek-mode) REALTEK_MODE=1; SET_RTK=1 ;;
        --no-realtek-mode) REALTEK_MODE=0; SET_RTK=1 ;;
        --no-module) MODULE=""; DRIVER=""; MODULE_SHA=""; SET_MODULE=1 ;;
        --file)
            shift
            DRIVER_FILE=$1
            [ -n "$DRIVER_FILE" ] || error_exit "--file needs the path to a downloaded driver module" ;;
        --no-mac) PIN_MAC=""; SET_MAC=1 ;;
        --json) JSON=1 ;;
        --phase) shift; PHASE=$1 ;;
        --check) CHECK_ONLY=1 ;;
        --last) LAST=1 ;;
        --no-wait) NO_WAIT=1 ;;
        --driver)
            shift
            DRIVER=$1; SET_MODULE=1
            case "$DRIVER" in ''|*[!A-Za-z0-9_]*) error_exit "--driver needs a driver name like r8152_oot" ;; esac ;;
        -h|--help|help) usage; exit 0 ;;
        -V|--version|version) echo "LG-USB-2-ETH0 v$VERSION"; exit 0 ;;
        install|uninstall|enable|disable|apply|revert|reset|status|doctor|report|get-driver|test-driver|speedtest|update) CMD=$1 ;;
        *) usage; error_exit "Unknown option: $1" ;;
    esac
    shift
done

case "$CMD" in
    install) install_fix ;;
    uninstall) uninstall_fix ;;
    enable) enable_fix ;;
    disable) disable_fix ;;
    apply) apply_now ;;
    revert|reset) revert_now ;;
    status|doctor) if [ "$JSON" = 1 ]; then show_json; else show_status; fi ;;
    report) show_report ;;
    get-driver) get_driver ;;
    test-driver) test_driver ;;
    speedtest) speed_test ;;
    update) if [ "$CHECK_ONLY" = 1 ]; then update_check; else update_now; fi ;;
    "") main_menu ;;
esac
