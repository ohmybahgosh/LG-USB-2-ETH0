# LG-USB-2-ETH0

<div align="center">

  ![GitHub stars](https://img.shields.io/github/stars/ohmybahgosh/LG-USB-2-ETH0?style=social)
  ![License](https://img.shields.io/badge/license-MIT-blue)
  ![Version](https://img.shields.io/badge/version-2.0-brightgreen)

  **Make a USB Ethernet adapter the TV's `eth0` on rooted LG webOS TVs, safely and at every boot**

  <img src="https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/refs/heads/main/USB-2-ETH0-BANNER.gif" alt="LG webOS USB Ethernet header image" />
</div>

## 🔍 Overview

LG TVs only have a 100 Mbit/s wired port. A gigabit USB Ethernet adapter is much faster, but webOS names it `eth1`, and parts of the TV only look at `eth0`. The result: the settings screen says "Not Connected" even though the internet works, and some streaming apps refuse to play.

This script renames the adapter to `eth0` and parks the built-in port under another name (`eth2`), so webOS and its apps treat the adapter as the TV's wired connection. A small boot hook redoes this at every start.

Created by [@ohmybahgosh](https://github.com/ohmybahgosh)

## 🚨 Problems Solved

| Issue | Impact | What this does |
|-------|--------|----------------|
| **Streaming app failures** | Apps like Paramount+ refuse to play over `eth1` | The adapter becomes `eth0` |
| **"Not Connected" in settings** | webOS shows no wired connection while the adapter works | Interface names match what webOS expects |
| **100 Mbit/s built-in port** | High bitrate remuxes, Plex and Moonlight stutter | Uses the faster adapter (see [Real speeds](#-real-speeds)) |

## ✨ What's new in 2.0

- **Never breaks the built-in port.** v1 renamed `eth0` to `eth2` at every boot even with no adapter plugged in, which left the TV with no `eth0` at all. v2 only touches anything when an adapter is actually there.
- **Waits for the adapter.** USB can come up after the boot hook runs. v2 waits in the background (120 s by default) and never holds up the Homebrew Channel startup.
- **Finds the adapter itself.** It checks that the device really is USB Ethernet, so it works when the adapter is `eth1`, `eth2` or `usb0`, and it never grabs the Wi-Fi module (which is a USB device on many LG TVs).
- **Rolls back on failure.** If a rename fails halfway, the old names are put back.
- **Safe live switching.** `apply` and `revert` run detached, so they finish even when your SSH session drops, and they warn you first if you're connected through a port that's about to change.
- **`status` / `doctor`.** Shows the hook, every interface (driver, MAC, cable, link speed, IP, USB 2.0 or 3.0), the drivers on your kernel, adapters the kernel sees but has no driver for, and the last boot log.
- **Disable that really disables.** v1 renamed the hook to `S01fix-eth.disabled` inside `init.d`, but busybox `run-parts` still runs names with dots, so on some TVs it kept running. v2 moves a disabled hook out of `init.d`.
- **Options:** pin one adapter by MAC (`--mac`), change the wait (`--wait`), load a driver module at boot (`--module`), and `-y` for scripts.

## 🛠️ Installation

### Prerequisites

- A rooted LG TV with the [Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel) (check yours at [cani.rootmy.tv](https://cani.rootmy.tv/))
- SSH (or telnet) access as root
- **Connect over Wi-Fi while you set this up.** Renaming takes the wired ports down for a moment.

### Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/main/LG-USB-2-ETH0.sh

# See what the TV has before changing anything
sh LG-USB-2-ETH0.sh status

# Install the boot hook (asks before it writes anything)
sh LG-USB-2-ETH0.sh install

# Optional: switch right now instead of at the next reboot
sh LG-USB-2-ETH0.sh apply
```

Or run `sh LG-USB-2-ETH0.sh` with no arguments for the menu:

```
=== LG-USB-2-ETH0 v2.0 ===
1) Install boot hook
2) Uninstall boot hook
3) Status and checks
4) Swap the adapter in now
5) Give eth0 back to the built-in port now
6) Disable boot hook
7) Enable boot hook
8) Exit
```

### Commands

| Command | What it does |
|---------|--------------|
| `install` | Writes the boot hook (`/var/lib/webosbrew/init.d/S01fix-eth`). Add `--now` to switch right away too. |
| `uninstall` | Removes the boot hook. Add `--now` to give `eth0` back to the built-in port right away. |
| `apply` | Swaps the adapter in now, without touching the hook. |
| `revert` | Gives `eth0` back to the built-in port now. (`reset` works too.) |
| `disable` / `enable` | Keeps the hook but stops it running at boot, or turns it back on. |
| `status` / `doctor` | Read-only report and checks. Safe to run any time. |

### Options

| Option | What it does |
|--------|--------------|
| `-y`, `--yes` | Answer yes to every question. |
| `--now` | With `install` or `uninstall`, also switch right away. |
| `--mac aa:bb:cc:dd:ee:ff` | Only ever promote that adapter. Handy with more than one adapter. |
| `--wait 120` | Seconds the boot hook waits for the adapter to appear. |
| `--module /home/root/r8152.ko` | Load this driver at boot before looking. Advanced, see [Adapter not detected](#adapter-not-detected). |

The options you install with are saved in the hook. Run `install` again to change them.

## 🔧 How it works

At boot the Homebrew Channel runs everything in `/var/lib/webosbrew/init.d`. The hook:

1. Starts a background job and returns at once, so other startup hooks and the Homebrew Channel's failsafe timer aren't held up.
2. Loads your `--module`, if you gave one.
3. Waits up to `--wait` seconds for a USB Ethernet adapter. A device counts only if it's wired Ethernet on the USB bus and not Wi-Fi, a phone or a modem.
4. If none turns up, it changes nothing and the built-in port stays `eth0`.
5. If one does, it renames the built-in `eth0` to `eth2`, the adapter to `eth0`, and brings both up. Any failed step puts the old names back.

It logs to `/tmp/lg-usb-2-eth0.log` (RAM, cleared at reboot). `status` shows the last lines.

Nothing else on the TV is changed: no driver files, no network settings. webOS still sets up the connection itself, the same way v1 relied on.

## 🧭 webOS compatibility

The script only needs root, the Homebrew Channel, `ip` and `/sys`, which every rooted webOS TV has. What decides whether this works on your TV is **whether its kernel has a driver for your adapter's chip**. That varies by model and firmware, not just by webOS version.

| webOS | What people have reported | Source |
|-------|---------------------------|--------|
| webOS 3.5 / 4 (2017-2018, B7, C7, C8) | ASIX based adapters (Cable Matters USB 3.0) work out of the box. TP-Link UE300 (Realtek RTL8153) didn't work on C7 or C8. Settings show "no connection" while apps work, which is the problem this script fixes. | [lgwebos.com thread](https://www.lgwebos.com/topic/3395-gigabit-ethernet-on-smart-tv/page/2/) |
| webOS 24 | What this script was originally written on. | |
| webOS 25 on a 2024 C4 | Realtek RTL8153 and RTL8156 adapters show up through the generic `cdc_ncm` driver. They work, but slower and with drops. A community-built `r8152` module helps. | [DonZoomik/webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| webOS 25 on 2024 QNED/OLED (Paparoa) | Reported that the Realtek driver was removed, so the adapter needs a module built for that exact kernel. | [mbenitez343/lg-webos-2024-ethernet-fix](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) |
| webOS 25 on a 2025 B5 | One report of an ASIX AX88179A not being detected at all. | [LG developer forum](https://forum.webostv.developer.lge.com/t/feature-request-usb-gigabit-ethernet-adapter-support-on-webos-25/28185) |

Run `sh LG-USB-2-ETH0.sh status` to see which drivers your kernel has and whether your adapter got one. If it says the adapter is plugged in but has no driver, renaming can't help until a driver is loaded.

**What's tested:** v2 was tested in simulation only (a fake `/sys` and a fake `ip`, under busybox `sh`, `dash` and `bash`): boot with and without the adapter, an adapter that shows up late, `usb0` naming, two adapters, MAC pinning, failed renames rolling back, revert, a session on the port being renamed, upgrade from v1, and disable with busybox `run-parts`. It hasn't been run on a TV yet. Reports from real TVs are very welcome.

## 📈 Real speeds

Don't expect gigabit. The TV's USB port and CPU are the limit. Measured by others:

- Built-in port: about 95 Mbit/s
- RTL8153 on a 2024 C4 (webOS 25) with `cdc_ncm`: about 200 to 255 Mbit/s, with drops
- Same adapter with the community `r8152` module: about 290 to 330 Mbit/s
- Cable Matters adapter on a 2018 C8: about 250 Mbit/s

That's still 2 to 3 times the built-in port, which is plenty for 4K remuxes. `status` tells you if your adapter landed on a USB 2.0 port.

## 🔄 Upgrading from v1

Run `sh LG-USB-2-ETH0.sh install`. It replaces the v1 hook in place (same file name). If you had "disabled" v1, `status` flags it: on TVs where `run-parts` is busybox's, the `.disabled` file kept running at boot. `disable` moves it out of `init.d`, or `install` replaces it.

## 🐛 Troubleshooting

**Lost SSH while switching?** The switch still finishes on the TV. Reconnect over Wi-Fi. The adapter has its own MAC address, so your router may give the TV a new IP. A DHCP reservation for the adapter's MAC keeps it steady.

**Want everything back the way it was?** `sh LG-USB-2-ETH0.sh uninstall --now`. Or just `uninstall` and reboot.

**Both cables plugged in?** Unplug the built-in one. With two wired links up, traffic can take the slower port.

**Settings still say "Not Connected", or no IP?** Run `status`. If the adapter is `eth0` but has no IPv4 address, give webOS a moment, then try unplugging and replugging the network cable.

<a id="adapter-not-detected"></a>**Adapter not detected?** `status` lists adapters the kernel sees but has no driver for. Try an adapter with a different chip (ASIX or Realtek), use a USB 3.0 port if the TV has one, or try a powered hub. If someone has built a driver module for your exact kernel (`uname -r`), install with `--module /full/path/driver.ko`. Only use a module built for your exact kernel.

**Something went wrong at boot?** The hook only renames interfaces (and loads your `--module`, if you gave one). It never touches system files, so a reboot always starts clean. If the Homebrew Channel drops into failsafe mode, telnet in, run `uninstall`, and reboot.

## 🤝 Contributing

Reports from real TVs help most: your model, webOS version, adapter chip, and the output of `status`. Pull requests are welcome.

## 📄 License

This project is licensed under the MIT License. See the LICENSE file for details.

## 👤 Author

**OhMyBahGosh**
GitHub: [@ohmybahgosh](https://github.com/ohmybahgosh)
Repository: [https://github.com/ohmybahgosh/LG-USB-2-ETH0](https://github.com/ohmybahgosh/LG-USB-2-ETH0)
