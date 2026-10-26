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

VERSION="2.0"

# === Color Codes ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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
OS_INFO="/var/run/nyx/os_info.json"
HBC_DIR="/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service"
MARKER="Managed by LG-USB-2-ETH0"

# === Defaults (install options) ===
ASSUME_YES=0
APPLY_NOW=0
PIN_MAC=""
WAIT_SECS=120
PARK_NAME="eth2"
MODULE=""

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
  version     Print the version

Options:
  -y, --yes          Answer yes to every question
  --now              With install or uninstall, also swap right away
  --mac MAC          Only ever promote the adapter with this MAC address
  --wait SECONDS     How long the boot hook waits for the adapter (default 120)
  --module FILE.ko   Load this driver module at boot before looking (advanced)
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

sysval() { [ -r "$1" ] && IFS= read -r _v < "$1" 2>/dev/null && printf '%s\n' "$_v"; }

is_wifi() { [ -d "$NET/$1/wireless" ] || [ -e "$NET/$1/phy80211" ]; }

nic_driver() {
    _l=$(readlink "$NET/$1/device/driver" 2>/dev/null) || return 0
    echo "${_l##*/}"
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

rename_if() { ip link set dev "$1" down && ip link set dev "$1" name "$2"; }

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

load_module() {
    [ -n "$MODULE" ] || return 0
    _m=${MODULE##*/}
    _m=${_m%.ko}
    if [ -d "/sys/module/$_m" ]; then
        echo "Module $_m already loaded."
    elif [ ! -r "$MODULE" ]; then
        echo "Module file $MODULE is missing. Skipping it."
    elif insmod "$MODULE"; then
        echo "Loaded module $MODULE."
    else
        echo "insmod $MODULE failed (built for another kernel?). See dmesg. Carrying on without it."
    fi
}

# What the boot hook does: wait for the adapter, then swap. The hook runs
# this in the background, so it never holds up the Homebrew Channel startup,
# and it changes nothing when no adapter shows up.
boot_run() {
    echo "=== $(date) boot hook (wait ${WAIT_SECS}s${PIN_MAC:+, MAC $PIN_MAC}) ==="
    load_module
    _t=0
    while [ "$_t" -lt "$WAIT_SECS" ] && [ -z "$(find_usb_nic)" ]; do
        sleep 2
        _t=$((_t + 2))
    done
    if [ -z "$(find_usb_nic)" ]; then
        echo "No USB Ethernet adapter after ${WAIT_SECS}s. Leaving the built-in port as eth0."
        return 0
    fi
    # Give a freshly attached adapter a moment to settle
    sleep 3
    swap_in
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
    [ -n "$WEBOS_RELEASE" ] || WEBOS_RELEASE=$(sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | tr -d '"')
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
    [ "$(id -u)" = 0 ] || error_exit "Run this as root on the TV (it needs a rooted TV)."
    [ -r "$OS_INFO" ] || command -v luna-send >/dev/null 2>&1 || \
        warn "This does not look like webOS. Carrying on, but check you're on the TV."
    command -v ip >/dev/null 2>&1 || error_exit "The 'ip' command is missing, so interfaces can't be renamed."
    ip link show >/dev/null 2>&1 || error_exit "'ip link' does not work here."
    [ -d "$NET" ] || error_exit "$NET is missing, so network devices can't be checked."
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
        echo "LOG_FILE=\"$LOG_FILE\""
        echo 'PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH'
        printf '%s\n' "$CORE"
        echo '# Keep the RAM log small'
        echo '[ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 32768 ] && mv -f "$LOG_FILE" "$LOG_FILE.1"'
        echo '( boot_run ) >> "$LOG_FILE" 2>&1 < /dev/null &'
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
    _job="PIN_MAC=\"$PIN_MAC\"; PARK_NAME=\"$PARK_NAME\"
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
    if [ -n "$MODULE" ] && [ ! -r "$MODULE" ]; then
        error_exit "Module file $MODULE does not exist."
    fi
    show_plan
    info "At every boot the hook will:"
    echo "  1. Wait up to ${WAIT_SECS}s in the background for a USB Ethernet adapter${PIN_MAC:+ with MAC $PIN_MAC}"
    [ -n "$MODULE" ] && echo "     (after loading $MODULE)"
    echo "  2. If one shows up, rename the built-in port to $PARK_NAME and the adapter to eth0"
    echo "  3. If none shows up, change nothing, so the built-in port keeps working"
    echo "It writes $HOOK and nothing else."
    case "$(hook_state)" in legacy|legacy-disabled)
        warn "This replaces the v1 hook, which renamed eth0 even with no adapter plugged in." ;;
    esac
    [ -z "$(find_usb_nic)" ] && warn "No adapter is visible right now. Run 'status' if it's plugged in."
    confirm "Install the boot hook?" || { echo "Cancelled. Nothing changed."; return 1; }
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

apply_now() { preflight; run_detached swap_in; }
revert_now() { preflight; run_detached swap_out; }

# Known USB Ethernet chips (vendor:product), to spot an adapter with no driver
known_nic_id() {
    case "$1" in
        0bda:8050|0bda:8052|0bda:8053|0bda:8152|0bda:8153|0bda:8155|0bda:8156|0bda:8157|0bda:815a) echo "Realtek RTL815x" ;;
        0b95:1790|0b95:178a|0b95:1780) echo "ASIX AX88179/178A" ;;
        0b95:7720|0b95:772a|0b95:772b|0b95:7e2b) echo "ASIX AX88772" ;;
        0424:7500|0424:7505|0424:9500|0424:ec00) echo "Microchip/SMSC" ;;
        0424:7800|0424:7801|0424:7850) echo "Microchip LAN78xx" ;;
        2357:0601|2357:0602) echo "TP-Link (Realtek)" ;;
        045e:07ab|045e:07c6|045e:0927|13b1:0041|0b05:1976|17ef:3052|17ef:3054|17ef:3069|17ef:3082|17ef:720c|17ef:7214) echo "OEM Realtek" ;;
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
            echo "$_s" ;;
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
        if [ "$_car" = 1 ]; then _line="cable in"; else _line="no cable"; fi
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
    for _m in r8152 ax88179_178a asix cdc_ether cdc_ncm smsc95xx lan78xx usbnet; do
        if [ -d "/sys/module/$_m" ]; then
            _list="$_list $_m(loaded)"
        elif [ -n "$(find "/lib/modules/$(uname -r)" -name "$_m.ko*" 2>/dev/null | head -n 1)" ]; then
            _list="$_list $_m(file)"
        fi
    done
    echo "  ${_list:-none found under /sys/module or /lib/modules}"

    _bi=$(find_builtin_nic)
    _usb=$(find_usb_nic)
    case "$(hook_state)" in
        enabled|legacy|legacy-disabled)
            [ "$_usb_seen" = 0 ] && status_note "The hook is on, but no adapter is visible now, so a boot right now would change nothing." ;;
    esac
    if [ -n "$_usb" ] && [ "$_usb" != eth0 ] && [ "$(hook_state)" = enabled ]; then
        status_note "The adapter is $_usb, not eth0 yet. Reboot, run 'apply', or check $LOG_FILE."
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
        echo "8) Exit"
        read_answer "Choose an option: " || exit 1
        case "$ANSWER" in
            1) install_fix ;;
            2) uninstall_fix ;;
            3) show_status ;;
            4) apply_now ;;
            5) revert_now ;;
            6) disable_fix ;;
            7) enable_fix ;;
            8|q|Q) echo "Bye."; exit 0 ;;
            *) echo "Pick 1 to 8." ;;
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
            case "$MODULE" in /*.ko) ;; *) error_exit "--module needs the full path to a .ko file" ;; esac ;;
        -h|--help|help) usage; exit 0 ;;
        -V|--version|version) echo "LG-USB-2-ETH0 v$VERSION"; exit 0 ;;
        install|uninstall|enable|disable|apply|revert|reset|status|doctor) CMD=$1 ;;
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
    "") main_menu ;;
esac
