# LG-USB-2-ETH0 

<div align="center">
  
  ![GitHub stars](https://img.shields.io/github/stars/ohmybahgosh/LG-USB-2-ETH0?style=social)
  ![License](https://img.shields.io/badge/license-MIT-blue)
  ![Version](https://img.shields.io/badge/version-1.0-brightgreen)
  
  **A POSIX-compliant shell utility that safely reassigns USB Ethernet adapters as `eth0` on rooted LG webOS 24+ TVs**
  
  <img src="https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/refs/heads/main/USB-2-ETH0-BANNER.gif" alt="LG webOS USB Ethernet header image" />
</div>

## 🔍 Overview

This utility solves a critical issue with LG TVs where USB Ethernet adapters are assigned as `eth1` instead of `eth0`, causing various streaming apps to malfunction and interface problems in the TV's UI.

Created by [@ohmybahgosh](https://github.com/ohmybahgosh)

## 🚨 Problems Solved

| Issue | Impact | Solution |
|-------|--------|----------|
| **Streaming app failures** | Apps like Paramount+ refuse to play video when using `eth1` | Forces USB adapter to be `eth0` |
| **UI reporting errors** | TV shows "Not Connected" despite having internet | Fixes interface naming to match UI expectations |
| **Speed limitations** | Built-in 100Mbps vs USB 2.0's 480Mbps potential | Prioritizes faster USB connection |
| **Compatibility issues** | System features expecting `eth0` specifically | Ensures proper interface naming for all services |

## ✨ Features

- **Lightweight**: POSIX `/bin/sh` compatible for webOS's minimal environment
- **Persistent**: Fully boot-persistent using webOS Homebrew's `init.d`
- **Simple**: Comprehensive menu-driven interface for all operations
- **Flexible**: Easy install/uninstall/enable/disable options
- **Clean**: Supports reverting legacy systemd installations

## 🛠️ Installation

### Prerequisites
- Rooted LG TV (webOS 24+)
- SSH access to your TV
- **Active Wi-Fi connection** (don't use USB Ethernet during setup)

### Quick Start

```bash
# Download the script
wget https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/main/LG-USB-2-ETH0.sh

# Make it executable
chmod +x LG-USB-2-ETH0.sh

# Run it
sh LG-USB-2-ETH0.sh
```

### Interactive Menu

Once running, you'll see the following options:

```
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

## 🔧 Technical Details

When installed, the script:

1. Creates `/var/lib/webosbrew/init.d/S01fix-eth`
2. Implements the following network interface reassignment logic:

```bash
ip link set eth0 down
ip link set eth0 name eth2
ip link set eth1 down
ip link set eth1 name eth0
ip link set eth0 up
ip link set eth2 up
```

3. Makes it executable and configured to auto-run at every boot

## 📋 Cleanup

If you previously used a systemd-based version of this fix, the menu provides an option (#4) to remove legacy service files for a clean state.

## 🐛 Troubleshooting

- **Lost SSH during setup?** Connect via Wi-Fi and try again
- **Apps still not working?** Verify the fix is running with option #3
- **Need to revert?** Use option #2 to uninstall

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👤 Author

**OhMyBahGosh**  
GitHub: [@ohmybahgosh](https://github.com/ohmybahgosh) 
