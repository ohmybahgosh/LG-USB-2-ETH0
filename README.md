
# LG-USB-2-ETH0

A POSIX-compliant shell utility that safely and persistently reassigns the USB Ethernet adapter as `eth0` on rooted LG webOS 24+ TVs.

Created by **OhMyBahGosh**

---

## 🚀 What This Fixes

Many LG TVs (including the C2) default to using the **built-in Ethernet as `eth0`** and assign USB Ethernet adapters to `eth1`. This causes problems like:

- **Slower performance:** Built-in Ethernet is often limited to 100 Mbps, while USB adapters can do 1 Gbps
- **Apps refusing to connect:** Some apps (like Paramount+) require the **active internet interface to be `eth0`**
- **Settings show “Not Connected”:** The network settings UI will show Ethernet disconnected when USB is `eth1`, even though it's active

This script reassigns the USB adapter to `eth0` **on boot**, resolving all the above issues.

---

## ✅ Features

- POSIX `/bin/sh` compatible — runs on webOS's minimal shell
- Reassigns `eth1` (USB adapter) to `eth0`
- Fully boot-persistent using Homebrew’s `init.d`
- Menu-driven tool to:
  - Install / Uninstall
  - Enable / Disable
  - Reinstall or Reset
  - Revert legacy systemd installs

---

## 📦 How to Use

### 1. Connect to your TV via SSH

Make sure you're **connected via Wi-Fi**, not USB Ethernet (`eth1`), or you’ll lose your SSH session during setup.

### 2. Clone the repo or download the script

```sh
wget https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/main/LG-USB-2-ETH0.sh
chmod +x LG-USB-2-ETH0.sh
sh LG-USB-2-ETH0.sh
```

### 3. Use the Menu

```text
=== LG-USB-2-ETH0 Fixer (init.d) ===
1) Install eth0 fix
2) Uninstall eth0 fix
3) Check fix status
4) Revert legacy systemd setup
5) Reinstall eth0 fix
6) Disable eth0 fix
7) Re-enable eth0 fix
8) Exit
9) Reset all Ethernet naming
```

---

## 🔧 What It Does Internally

When installed, the script:

1. Creates `/var/lib/webosbrew/init.d/S01fix-eth`
2. Adds the following logic:

   ```sh
   ip link set eth0 down
   ip link set eth0 name eth2
   ip link set eth1 down
   ip link set eth1 name eth0
   ip link set eth0 up
   ip link set eth2 up
   ```

3. Makes it executable and auto-run at every boot

---

## 🧼 Optional Cleanup

If you've used a prior systemd-based version, the menu provides an option to **remove legacy service and timer files** for a clean state.

---

## 👤 Author

**OhMyBahGosh**  
GitHub: [@ohmybahgosh](https://github.com/ohmybahgosh)
