#!/bin/sh

###############################################################################
# LG-USB-2-ETH0 Fixer for webOS (init.d version only)
# Safely remaps USB Ethernet adapter to eth0 using init.d on rooted LG TVs
# Author: OhMyBahGosh
# Repository: https://github.com/ohmybahgosh/LG-USB-2-ETH0
# Version: 1.0.1
###############################################################################

# ANSI color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Paths
INIT_DIR="/var/lib/webosbrew/init.d"
INIT_SCRIPT="$INIT_DIR/S01fix-eth"
DISABLED_SCRIPT="$INIT_DIR/S01fix-eth.disabled"

install_fix() {
  printf "${CYAN}Installing eth0 fix using init.d...${RESET}\n"
  mkdir -p "$INIT_DIR"
  cat << 'EOF' > "$INIT_SCRIPT"
#!/bin/sh
ip link set eth0 down
ip link set eth0 name eth2
ip link set eth1 down
ip link set eth1 name eth0
ip link set eth0 up
ip link set eth2 up
EOF
  chmod +x "$INIT_SCRIPT"
  printf "${GREEN}Install complete. Fix will run at every boot.${RESET}\n"
}

uninstall_fix() {
  printf "${YELLOW}Uninstalling init.d fix...${RESET}\n"
  rm -f "$INIT_SCRIPT" "$DISABLED_SCRIPT"
  printf "${GREEN}Uninstall complete.${RESET}\n"
}

disable_fix() {
  if [ -f "$INIT_SCRIPT" ]; then
    mv "$INIT_SCRIPT" "$DISABLED_SCRIPT"
    printf "${YELLOW}Fix disabled. It won't run on boot.${RESET}\n"
  else
    printf "${RED}Fix is not currently enabled.${RESET}\n"
  fi
}

enable_fix() {
  if [ -f "$DISABLED_SCRIPT" ]; then
    mv "$DISABLED_SCRIPT" "$INIT_SCRIPT"
    chmod +x "$INIT_SCRIPT"
    printf "${GREEN}Fix re-enabled. It will now run on boot.${RESET}\n"
  else
    printf "${RED}No disabled fix found to re-enable.${RESET}\n"
  fi
}

check_status() {
  printf "${CYAN}Checking eth0 fix status...${RESET}\n"
  if [ -x "$INIT_SCRIPT" ]; then
    printf "${GREEN}✓ Installed and enabled via init.d (${INIT_SCRIPT})${RESET}\n"
  elif [ -f "$DISABLED_SCRIPT" ]; then
    printf "${YELLOW}⚠ Installed but disabled (${DISABLED_SCRIPT})${RESET}\n"
  else
    printf "${RED}✗ Not installed via init.d${RESET}\n"
  fi
}

reset_eth_naming() {
  printf "${YELLOW}Resetting Ethernet interface names...${RESET}\n"

  ip link set eth0 down 2>/dev/null
  ip link set eth1 down 2>/dev/null
  ip link set eth2 down 2>/dev/null

  ip link set eth0 name ethX 2>/dev/null
  ip link set eth1 name ethY 2>/dev/null

  ip link set ethX name eth1 2>/dev/null
  ip link set eth2 name eth0 2>/dev/null
  ip link set ethY name eth2 2>/dev/null

  ip link set eth0 up 2>/dev/null
  ip link set eth1 up 2>/dev/null
  ip link set eth2 up 2>/dev/null

  printf "${GREEN}Attempted to reset Ethernet naming. Current layout:${RESET}\n"
  ip addr show | grep -E "^[0-9]+: eth"
}

warn_if_using_eth1() {
  DEFAULT_IFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
  if [ "$DEFAULT_IFACE" = "eth1" ]; then
    printf "${RED}WARNING: You're connected via eth1 (USB Ethernet).${RESET}\n"
    echo "Renaming eth1 to eth0 will disconnect SSH."
    echo "Please connect to Wi-Fi before continuing."
    printf "Continue anyway? [y/N]: "
    read CONFIRM
    if [ "$CONFIRM" != "y" ]; then
      echo "Aborted."
      exit 1
    fi
  fi
}

main_menu() {
  while true; do
    echo ""
    printf "${CYAN}=== LG-USB-2-ETH0 Fixer (init.d) ===${RESET}\n"
    echo "1) Install eth0 fix"
    echo "2) Uninstall eth0 fix"
    echo "3) Check fix status"
    echo "4) Reinstall eth0 fix"
    echo "5) Disable eth0 fix"
    echo "6) Re-enable eth0 fix"
    echo "7) Reset all Ethernet naming"
    echo "8) Exit"
    printf "Choose an option: "
    read CHOICE

    case "$CHOICE" in
      1) warn_if_using_eth1; install_fix ;;
      2) uninstall_fix ;;
      3) check_status ;;
      4) uninstall_fix; warn_if_using_eth1; install_fix ;;
      5) disable_fix ;;
      6) enable_fix ;;
      7) reset_eth_naming ;;
      8) echo "Goodbye!"; exit 0 ;;
      *) echo "Invalid option." ;;
    esac

    echo ""
    echo "Press Enter to return to the menu..."
    read dummy
    clear
  done
}

main_menu
