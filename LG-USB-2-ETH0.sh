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

VERSION="2.2"

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
LOG_FILE="${LGU2E_ROOT}/tmp/lg-usb-2-eth0.log"
# The boot hook's background job writes its process ID here
PID_FILE="${LGU2E_ROOT}/tmp/lg-usb-2-eth0.pid"
OS_INFO="${LGU2E_ROOT}/var/run/nyx/os_info.json"
HBC_DIR="/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service"
MARKER="Managed by LG-USB-2-ETH0"
# Where get-driver keeps downloaded driver modules (persistent storage)
DRIVER_DIR="${LGU2E_ROOT}/home/root/lg-usb-2-eth0/drivers"
# DonZoomik's own boot hook for r8152_oot, which does the same job as --module
AUTOBIND_HOOK="$INIT_DIR/90-r8152-oot"

# === Defaults (install options) ===
ASSUME_YES=0
APPLY_NOW=0
PIN_MAC=""
WAIT_SECS=120
PARK_NAME="eth2"
MODULE=""
DRIVER=""
WATCH=0

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
  get-driver  Download a better driver module known to work on this exact
              kernel, if there is one, and check its checksum
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

load_module() {
    [ -n "$MODULE" ] || return 0
    _m=${DRIVER:-${MODULE##*/}}
    _m=${_m%.ko}
    if [ -d "$SYS_MODULES/$_m" ]; then
        echo "Module $_m already loaded."
    elif [ ! -r "$MODULE" ]; then
        echo "Module file $MODULE is missing. Skipping it."
    elif insmod "$MODULE"; then
        echo "Loaded module $MODULE."
    else
        echo "insmod $MODULE failed (built for another kernel?). See dmesg. Carrying on without it."
    fi
}

# True when any interface of USB device $1 is bound to $DRIVER
on_driver() {
    for _i in "$USB_DEVS/$1"/*:*; do
        [ "$(nic_driver_path "$_i")" = "$DRIVER" ] && return 0
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

# Driver takeover. The kernel gives many Realtek adapters to the generic
# cdc_ncm driver, even when a better driver module is loaded. Move each one
# over to $DRIVER. If that doesn't take within a few seconds, give it back to
# cdc_ncm. Each device gets one try per boot, so a driver that doesn't support
# it can't cause repeated drops.
TAKEOVER_STATE=${LOG_FILE%.log}.takeover
take_over() {
    [ -n "$DRIVER" ] || return 0
    if [ ! -d "$USB_DRIVERS/$DRIVER" ]; then
        echo "Driver $DRIVER is not loaded, so the adapter stays on its current driver."
        return 0
    fi
    for _p in "$NET"/*; do
        _n=${_p##*/}
        is_usb_nic "$_n" || continue
        [ "$(nic_driver "$_n")" = cdc_ncm ] || continue
        _ifc=$(readlink -f "$NET/$_n/device") || continue
        _in=${_ifc##*/}
        _dev=${_in%%:*}
        _tok="$(sysval "$USB_DEVS/$_dev/busnum"):$(sysval "$USB_DEVS/$_dev/devnum"):$(sysval "$USB_DEVS/$_dev/idVendor"):$(sysval "$USB_DEVS/$_dev/idProduct")"
        grep -qx "$_tok" "$TAKEOVER_STATE" 2>/dev/null && continue
        echo "$_tok" >> "$TAKEOVER_STATE"
        echo "USB $_n ($_dev, $(sysval "$USB_DEVS/$_dev/idVendor"):$(sysval "$USB_DEVS/$_dev/idProduct")): cdc_ncm -> $DRIVER"
        if ! sys_write "$USB_DRIVERS/cdc_ncm/unbind" "$_in" 2>/dev/null; then
            echo "Could not release it from cdc_ncm. Leaving it as it is."
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
        echo "$DRIVER did not take it. Giving it back to cdc_ncm."
        [ -d "$_ifc" ] && sys_write "$USB_DRIVERS/cdc_ncm/bind" "$_in" 2>/dev/null
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
watch_run() {
    echo "Watching for the adapter (every ${WATCH_EVERY}s)."
    _skip=""
    while :; do
        sleep "$WATCH_EVERY"
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
    [ "$WATCH" = 1 ] && watch_run
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
    _vm=$(tr -c '[:alnum:]_=.+ -' '\n' < "$MODULE" 2>/dev/null | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | head -n 1)
    if [ -n "$_vm" ] && [ "$_vm" != "$(uname -r)" ]; then
        error_exit "$MODULE is built for kernel $_vm, but this TV runs $(uname -r). Loading it could crash the TV."
    fi
}

# For apply: use the installed hook's module unless one was given
use_hook_driver() {
    if [ -z "$MODULE" ] && [ "$(hook_state)" = enabled ]; then
        MODULE=$(hook_setting MODULE)
        DRIVER=$(hook_setting DRIVER)
    fi
    resolve_driver
}

# Better driver modules known to work on one exact kernel, as
# "url sha256 file author-page". They're built and published by their
# authors. get-driver checks the SHA-256 before keeping a download.
known_driver() {
    case "$1" in
        5.4.268-329.ptl4tv.5)
            echo "https://raw.githubusercontent.com/DonZoomik/webos-r8152/1ea8e98a24ef7443c590024d48947fee22d29cf1/r8152_oot.ko fe1691622747c106af44f7834675ec75ca3327a797c6bbec394e2998db66e8cb r8152_oot.ko https://github.com/DonZoomik/webos-r8152" ;;
        *) return 1 ;;
    esac
}

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$1" "$2"
    elif command -v wget >/dev/null 2>&1; then wget -q -O "$1" "$2"
    else echo "Neither curl nor wget is available."; return 1
    fi
}

get_driver() {
    preflight
    _k=$(uname -r)
    _kd=$(known_driver "$_k") || {
        info "No known better driver for kernel $_k."
        echo "If someone has built one for this exact kernel, install it with --module /full/path/driver.ko."
        return 0
    }
    # shellcheck disable=SC2086 # split the fields on purpose
    set -- $_kd
    _url=$1 _sum=$2 _file=$3 _page=$4
    _dest="$DRIVER_DIR/$_file"
    info "Kernel $_k has a known better driver: $_file"
    echo "  Built and published by: $_page"
    echo "  Download: $_url"
    echo "  It's a kernel module from that project, not from LG-USB-2-ETH0. It's only offered"
    echo "  for this exact kernel, and its SHA-256 is checked before it's kept."
    if [ -f "$_dest" ] && [ "$(sha256sum "$_dest" | awk '{print $1}')" = "$_sum" ]; then
        success "Already downloaded and verified: $_dest"
    else
        confirm "Download it?" || { echo "Cancelled. Nothing changed."; return 1; }
        mkdir -p "$DRIVER_DIR" || error_exit "Could not create $DRIVER_DIR."
        fetch "$_dest.part" "$_url" || { rm -f "$_dest.part"; error_exit "Download failed."; }
        _got=$(sha256sum "$_dest.part" | awk '{print $1}')
        if [ "$_got" != "$_sum" ]; then
            rm -f "$_dest.part"
            error_exit "Checksum mismatch (got $_got). The file was deleted and nothing changed."
        fi
        mv -f "$_dest.part" "$_dest" || error_exit "Could not save $_dest."
        success "Downloaded and verified: $_dest"
    fi
    echo "Install it with:"
    echo "  sh $0 install --module $_dest"
}

# === Hook state ===
hook_state() {
    if [ -f "$HOOK" ]; then
        if grep -q "$MARKER" "$HOOK" 2>/dev/null; then echo enabled; else echo legacy; fi
    elif [ -f "$OLD_DISABLED_HOOK" ]; then
        echo legacy-disabled
    elif [ -f "$DISABLED_HOOK" ]; then
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

hook_setting() {
    _f=$HOOK
    [ -f "$_f" ] || _f=$DISABLED_HOOK
    sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$_f" 2>/dev/null | head -n 1
}

# shellcheck disable=SC2016 # the hook expands these itself at boot
write_hook() {
    mkdir -p "$INIT_DIR" || error_exit "Could not create $INIT_DIR."
    _tmp="$HOOK.new"
    {
        echo '#!/bin/sh'
        echo "# $MARKER v$VERSION. Change it with the LG-USB-2-ETH0 script, not by hand."
        echo "# Waits in the background for a USB Ethernet adapter, then makes it eth0."
        echo "PIN_MAC=\"$PIN_MAC\""
        echo "WAIT_SECS=\"$WAIT_SECS\""
        echo "PARK_NAME=\"$PARK_NAME\""
        echo "MODULE=\"$MODULE\""
        echo "DRIVER=\"$DRIVER\""
        echo "WATCH=\"$WATCH\""
        echo "PID_FILE=\"$PID_FILE\""
        echo "LOG_FILE=\"$LOG_FILE\""
        echo 'PATH=$PATH:/usr/sbin:/usr/bin:/sbin:/bin'
        printf '%s\n' "$CORE"
        echo '# Keep the RAM log small'
        echo '[ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 32768 ] && mv -f "$LOG_FILE" "$LOG_FILE.1"'
        echo '( boot_run ) >> "$LOG_FILE" 2>&1 < /dev/null &'
        echo 'echo $! > "$PID_FILE"'
        echo 'exit 0'
    } > "$_tmp" || error_exit "Could not write $_tmp."
    { chmod 755 "$_tmp" && mv -f "$_tmp" "$HOOK"; } || error_exit "Could not install $HOOK."
    rm -f "$DISABLED_HOOK" "$OLD_DISABLED_HOOK"
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
    _job="PIN_MAC=\"$PIN_MAC\"; PARK_NAME=\"$PARK_NAME\"; MODULE=\"$MODULE\"; DRIVER=\"$DRIVER\"
LOG_FILE=\"$LOG_FILE\"
$CORE
$_what"
    : > "$LOG_FILE.now"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh -c "$_job" > "$LOG_FILE.now" 2>&1 < /dev/null &
    else
        nohup sh -c "$_job" > "$LOG_FILE.now" 2>&1 < /dev/null &
    fi
    _pid=$!
    _i=0
    while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 20 ]; do
        sleep 1
        _i=$((_i + 1))
    done
    cat "$LOG_FILE.now" 2>/dev/null
    if kill -0 "$_pid" 2>/dev/null; then
        warn "Still working in the background. Run 'status' in a minute to see how it went."
    fi
    { echo "=== $(date) $_what (by hand) ==="; cat "$LOG_FILE.now"; } >> "$LOG_FILE" 2>/dev/null
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
    resolve_driver
    show_plan
    info "At every boot the hook will:"
    echo "  1. Wait up to ${WAIT_SECS}s in the background for a USB Ethernet adapter${PIN_MAC:+ with MAC $PIN_MAC}"
    [ -n "$MODULE" ] && echo "     (after loading $MODULE, and moving the adapter from cdc_ncm to $DRIVER)"
    echo "  2. If one shows up, rename the built-in port to $PARK_NAME and the adapter to eth0"
    echo "  3. If none shows up, change nothing, so the built-in port keeps working"
    [ "$WATCH" = 1 ] && echo "  4. Keep watching: swap the adapter in when it's plugged in, give eth0 back when it's unplugged"
    echo "It writes $HOOK and nothing else."
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
    if [ "$APPLY_NOW" = 1 ]; then
        run_detached swap_in
    else
        echo "It takes effect at the next reboot. Run 'apply' to switch now."
    fi
}

uninstall_fix() {
    preflight
    if [ "$(hook_state)" = none ]; then
        info "No boot hook installed."
    else
        confirm "Remove the boot hook?" || { echo "Cancelled. Nothing changed."; return 1; }
        stop_watcher
        rm -f "$HOOK" "$DISABLED_HOOK" "$OLD_DISABLED_HOOK" "$HOOK.new" || error_exit "Could not remove the hook."
        success "Boot hook removed."
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
        enabled|legacy)
            stop_watcher
            { chmod 644 "$HOOK" && mv -f "$HOOK" "$DISABLED_HOOK"; } || error_exit "Could not disable the hook."
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
        enabled|legacy) info "The hook is already enabled."; return 0 ;;
        *) warn "No boot hook installed. Use 'install'."; return 0 ;;
    esac
    { mv -f "$_from" "$HOOK" && chmod 755 "$HOOK"; } || error_exit "Could not enable the hook."
    success "Hook enabled. It runs at the next boot."
    grep -q "$MARKER" "$HOOK" || warn "This is the v1 hook. Run 'install' to upgrade it."
}

apply_now() {
    preflight
    use_hook_driver
    if [ -n "$DRIVER" ]; then
        rm -f "$TAKEOVER_STATE"
        run_detached "load_module; take_over; wait_for_nic; swap_in"
    else
        run_detached swap_in
    fi
}
revert_now() { preflight; run_detached swap_out; }

# Known USB Ethernet chips (vendor:product), to spot an adapter with no driver
known_nic_id() {
    case "$1" in
        0bda:8050|0bda:8052|0bda:8053|0bda:8151|0bda:8152|0bda:8153|0bda:8155|0bda:8156|0bda:8157|0bda:815a) echo "Realtek RTL815x" ;;
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

iface_ipv4() { ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4; exit}'; }

show_status() {
    ISSUES=0
    NOTES=""
    echo
    log "$CYAN" "=== LG-USB-2-ETH0 v$VERSION status ==="
    print_tv

    echo
    log "$CYAN" "Boot hook"
    case "$(hook_state)" in
        enabled)
            log "$GREEN" "  Installed and enabled ($HOOK)"
            _s="  Waits $(hook_setting WAIT_SECS)s"
            [ -n "$(hook_setting PIN_MAC)" ] && _s="$_s, only for MAC $(hook_setting PIN_MAC)"
            [ -n "$(hook_setting MODULE)" ] && _s="$_s, loads $(hook_setting MODULE)"
            [ -n "$(hook_setting DRIVER)" ] && _s="$_s (driver $(hook_setting DRIVER))"
            [ "$(hook_setting WATCH)" = 1 ] && _s="$_s, keeps watching (--watch)"
            echo "$_s"
            _w=$(watcher_pid) && echo "  Background job running (PID $_w)" ;;
        legacy)
            log "$YELLOW" "  Old v1 hook installed. It renames eth0 even with no adapter plugged in."
            status_issue "Run 'install' to replace the v1 hook." ;;
        legacy-disabled)
            log "$YELLOW" "  Old v1 hook, \"disabled\" inside init.d ($OLD_DISABLED_HOOK)"
            status_issue "Busybox run-parts may still run that file at boot. Run 'disable' to move it out, or 'install' to upgrade." ;;
        disabled) log "$YELLOW" "  Installed but disabled ($DISABLED_HOOK)" ;;
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
    for _m in r8152 $_hd r8152_oot ax88179_178a asix cdc_ether cdc_ncm smsc95xx lan78xx usbnet; do
        case " $_seen " in *" $_m "*) continue ;; esac
        _seen="$_seen $_m"
        if [ -d "$SYS_MODULES/$_m" ]; then
            _list="$_list $_m(loaded)"
        elif [ -n "$(find "/lib/modules/$(uname -r)" -name "$_m.ko*" 2>/dev/null | head -n 1)" ]; then
            _list="$_list $_m(file)"
        fi
    done
    if [ -n "$_list" ]; then echo "  ${_list# }"; else echo "  none found under /sys/module or /lib/modules"; fi

    _bi=$(find_builtin_nic)
    _usb=$(find_usb_nic)
    if [ -n "$_usb" ] && [ "$(nic_driver "$_usb")" = cdc_ncm ]; then
        if [ -n "$_hd" ]; then
            status_note "$_usb is still on cdc_ncm, not $_hd. Run 'apply', or check $LOG_FILE."
        elif known_driver "$(uname -r)" >/dev/null; then
            status_note "$_usb uses the generic cdc_ncm driver. A faster, steadier driver is known for this kernel: run 'get-driver'."
        fi
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
status_issue() { log "$RED" "  ! $1"; ISSUES=$((ISSUES + 1)); }
status_note() { NOTES="$NOTES
  - $1"; }

# Hide the device-specific half of a MAC address in reports
mask_mac() { echo "$1" | sed 's/^\(..:..:..\):.*/\1:xx:xx:xx/'; }

# Short, paste-ready report for GitHub issues. MAC addresses are masked.
show_report() {
    tv_info
    echo '```'
    echo "LG-USB-2-ETH0 v$VERSION report"
    echo "Model:   ${TV_MODEL:-unknown}"
    echo "webOS:   $WEBOS_NAME (${WEBOS_RELEASE:-unknown}), firmware ${FIRMWARE:-unknown}"
    echo "Kernel:  $(uname -r) ($(uname -m))"
    _h=$(hook_state)
    if [ "$_h" = enabled ]; then
        _h="$_h, wait $(hook_setting WAIT_SECS)s"
        [ -n "$(hook_setting PIN_MAC)" ] && _h="$_h, pinned MAC"
        [ -n "$(hook_setting MODULE)" ] && _h="$_h, module $(basename "$(hook_setting MODULE)")"
        [ "$(hook_setting WATCH)" = 1 ] && _h="$_h, watch"
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
        [ -d "$SYS_MODULES/$_m" ] && _list="$_list $_m"
    done
    echo "Drivers loaded:${_list:- none}"
    echo "Default route: $(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
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
        echo "9) Get a better driver for this TV"
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
            9) get_driver ;;
            0|q|Q) echo "Bye."; exit 0 ;;
            *) echo "Pick 0 to 9." ;;
        esac
        read_answer "Press Enter for the menu..." || exit 0
    done
}

# === Arguments ===
CMD=""
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --now) APPLY_NOW=1 ;;
        --mac)
            shift
            PIN_MAC=$(echo "$1" | tr 'A-F' 'a-f')
            echo "$PIN_MAC" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || error_exit "--mac needs a MAC like aa:bb:cc:dd:ee:ff" ;;
        --wait)
            shift
            WAIT_SECS=$1
            case "$WAIT_SECS" in ''|*[!0-9]*) error_exit "--wait needs a number of seconds" ;; esac ;;
        --module)
            shift
            MODULE=$1
            case "$MODULE" in /*.ko) ;; *) error_exit "--module needs the full path to a .ko file" ;; esac
            # It is written into a root boot script, so only allow plain path characters
            case "$MODULE" in *[!A-Za-z0-9._/-]*) error_exit "--module path may only use letters, digits, '.', '_', '-' and '/'" ;; esac ;;
        --watch) WATCH=1 ;;
        --driver)
            shift
            DRIVER=$1
            case "$DRIVER" in ''|*[!A-Za-z0-9_]*) error_exit "--driver needs a driver name like r8152_oot" ;; esac ;;
        -h|--help|help) usage; exit 0 ;;
        -V|--version|version) echo "LG-USB-2-ETH0 v$VERSION"; exit 0 ;;
        install|uninstall|enable|disable|apply|revert|reset|status|doctor|report|get-driver) CMD=$1 ;;
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
    status|doctor) show_status ;;
    report) show_report ;;
    get-driver) get_driver ;;
    "") main_menu ;;
esac
