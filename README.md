<div align="center">

# LG-USB-2-ETH0

**Make a USB Ethernet adapter the TV's `eth0` on rooted LG webOS TVs, safely and at every boot.**

[![CI](https://github.com/ohmybahgosh/LG-USB-2-ETH0/actions/workflows/ci.yml/badge.svg)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ohmybahgosh/LG-USB-2-ETH0?sort=semver)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Listed in awesome-webos](https://img.shields.io/badge/listed%20in-awesome--webos-fc60a8)](https://github.com/tolgakurtuluss/awesome-webos)
[![Project page](https://img.shields.io/badge/ohmybahgosh.dev-project%20page-3ddc97)](https://ohmybahgosh.dev/lg-usb-2-eth0/)
[![GitHub stars](https://img.shields.io/github/stars/ohmybahgosh/LG-USB-2-ETH0?style=social)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/stargazers)

<img src="assets/banner.svg" width="100%" alt="LG-USB-2-ETH0: a terminal on the TV runs apply, the built-in port becomes eth2 and the USB adapter becomes eth0" />

</div>

LG TVs ship with a 100 Mbit/s wired port.  A gigabit USB adapter is two to three times faster on the same TV, even on the USB 2.0 ports many models have (a 2022 C2 included), but webOS names it `eth1`, and parts of webOS only look at `eth0`.  So the settings screen says "Not Connected" while the internet works, and some streaming apps refuse to play.

This script renames the adapter to `eth0` and parks the built-in port under another name, so webOS and its apps treat the adapter as the TV's wired connection.  A small boot hook does it again at every start.

> [!TIP]
> **Is it safe, and how do I undo it?**
> It adds one boot hook, a link at `/var/lib/webosbrew/init.d/S01fix-eth`, keeps its settings in `/var/lib/webosbrew/lg-usb-2-eth0.conf`, and only renames network interfaces.  No system files or network settings are touched, so a reboot without the hook always starts clean.  With no adapter plugged in, the hook changes nothing.
> Undo everything with **Turn everything off** in the TV app, or `sh LG-USB-2-ETH0.sh uninstall --now`.

## Contents

- [The TV app](#the-tv-app)
- [Quick start](#quick-start)
- [What it fixes](#what-it-fixes)
- [Commands and options](#commands-and-options)
- [How it works](#how-it-works)
- [Choosing an adapter](#choosing-an-adapter)
- [A faster driver for Realtek adapters](#a-faster-driver-for-realtek-adapters)
- [webOS compatibility](#webos-compatibility)
- [Real speeds](#real-speeds)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Upgrading from v1](#upgrading-from-v1)
- [Development and tests](#development-and-tests)
- [Contributing](#contributing)
- [Thanks](#thanks)

## The TV app

The easiest way in.  It runs the same script underneath, as root through the Homebrew Channel, so you don't need SSH at all.

- **Status at a glance:** whether the adapter is `eth0`, its driver, link speed, USB bus, address, Wi-Fi, and any problems found.
- **Run at every boot**, **Follow plug and unplug**, and **Switch now**, as on/off switches.
- **Faster Realtek driver:** only shows up when a driver is known for your TV's exact kernel and a Realtek adapter is plugged in.  It downloads, checks and sets up the driver in one go.
- **Speed test:** download, upload and latency through the TV's current connection, against Cloudflare's nearest server.
- **Report for GitHub:** a QR code that opens a compatibility report on your phone with your TV, adapter, speed and the full report already filled in (MAC addresses hidden).
- **Updates:** tells you when a new version is out.  If you installed through the Homebrew Channel repo below, the update comes from there.  Otherwise the app downloads it, checks its SHA-256, and installs it itself.
- **Turn everything off:** removes the boot hook and gives `eth0` back to the built-in port.  Do this before you remove the app.

**Install it from the Homebrew Channel:** open the Homebrew Channel, go to Settings, add the repository `https://ohmybahgosh.dev/repo`, then install **LG-USB-2-ETH0** from the list.  The Homebrew Channel then offers updates like for any other app.

**Or install the IPK yourself:** download `org.ohmybahgosh.lgusb2eth0_*.ipk` from the [latest release](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest) and install it with `ares-install`, or on the TV:

```sh
luna-send -n 1 luna://com.webos.appInstallService/dev/install '{"id":"org.ohmybahgosh.lgusb2eth0","ipkUrl":"/tmp/org.ohmybahgosh.lgusb2eth0_2.3.0_all.ipk"}'
```

Already set up with the script over SSH?  Open the app and it picks up your settings.  Its boot hook links to the copy of the script inside the app, so the app and the hook always run the same version.

## Quick start

Prefer SSH, or want to see every step?  This is the same thing without the app.

You need:

- A rooted LG TV with the [Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel).  Check yours at [cani.rootmy.tv](https://cani.rootmy.tv/).
- SSH (or telnet) access as root.
- **A Wi-Fi connection while you set this up.**  Renaming takes the wired ports down for a moment.

On the TV:

```sh
cd /tmp

# Download the latest release and its checksum
curl -fsSLO https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/LG-USB-2-ETH0.sh
curl -fsSLO https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS

# See what the TV has before changing anything (read-only)
sh LG-USB-2-ETH0.sh status

# Install the boot hook (asks before it writes anything)
sh LG-USB-2-ETH0.sh install

# Optional: switch right now instead of at the next reboot
sh LG-USB-2-ETH0.sh apply
```

No `curl`?  Use `wget` the same way.  If both fail with a TLS error (common on older firmware), download the two files on your computer and copy them over with `scp`.

Run `sh LG-USB-2-ETH0.sh` with no arguments for a menu.

<details>
<summary>What <code>status</code> looks like once it's working</summary>

```
=== LG-USB-2-ETH0 v2.3 status ===
Model:     OLED65C2PUA
webOS:     webOS 25 (10.x), firmware 33.x
Kernel:    aarch64, 5.4.x

Boot hook
  Installed and enabled (/var/lib/webosbrew/init.d/S01fix-eth -> /home/root/lg-usb-2-eth0/LG-USB-2-ETH0.sh)
  Waits 120s

Network interfaces
  eth0      USB Ethernet       driver r8152          00:e0:4c:68:12:34
            cable in, link 1000 Mbit/s, IPv4 192.168.1.42/24, on USB 2.0
  eth2      built-in Ethernet  driver lg-eth         a8:23:fe:00:00:01
            no cable, IPv4 none
  wlan0     Wi-Fi              driver mt7601u        00:11:22:33:44:55
            connected, IPv4 none
  Default route: eth0

USB network drivers on this kernel
  r8152(loaded) cdc_ncm(loaded) usbnet(loaded)

The USB adapter is eth0 and the built-in port is eth2.

Last log lines (/var/lib/webosbrew/lg-usb-2-eth0.log)
  Built-in eth0 -> eth2
  USB eth1 (r8152) -> eth0
  Done: the USB adapter is eth0, the built-in port is eth2.

No problems found.
```

This sample comes from the test suite, with example TV details filled in.  Your model, firmware and driver names will differ.

</details>

## What it fixes

| Problem | What you see | What this does |
|---------|--------------|----------------|
| **Streaming apps fail** | Apps like Paramount+ refuse to play over `eth1` | The adapter becomes `eth0` |
| **"Not Connected" in settings** | webOS shows no wired connection while the adapter works | Interface names match what webOS expects |
| **100 Mbit/s built-in port** | High-bitrate remuxes, Plex and Moonlight stutter | Uses the faster adapter (see [Real speeds](#real-speeds)) |

## Commands and options

| Command | What it does |
|---------|--------------|
| `install` | Writes the boot hook.  Add `--now` to switch right away too. |
| `uninstall` | Removes the boot hook.  Add `--now` to give `eth0` back to the built-in port right away. |
| `apply` | Swaps the adapter in now, without touching the hook. |
| `revert` | Gives `eth0` back to the built-in port now.  (`reset` works too.) |
| `disable` / `enable` | Keeps the hook but stops it running at boot, or turns it back on. |
| `status` / `doctor` | Read-only report and checks.  Safe to run any time. |
| `report` | Short, paste-ready report for a GitHub issue.  MAC addresses are masked. |
| `get-driver` | Downloads a better driver module, if one is known to work on your exact kernel, and checks its checksum.  With `--file PATH`, checks and uses a copy you downloaded yourself.  See [A faster driver](#a-faster-driver-for-realtek-adapters). |
| `speedtest` | Latency, download and upload through the TV's current connection, against Cloudflare's nearest server.  Four streams for about six seconds each way, so it uses a few hundred MB.  The last result shows up in `report` and the app. |
| `update` | Checks for a newer release and installs it, after checking its SHA-256.  `--check` only checks.  Inside the app, it updates the whole app.  On its own, the script replaces itself (and the boot hook's copy).  Your settings stay. |

| Option | What it does |
|--------|--------------|
| `-y`, `--yes` | Answer yes to every question. |
| `--now` | With `install` or `uninstall`, also switch right away. |
| `--watch` | Keep watching after boot.  Plug the adapter in and it becomes `eth0`; unplug it and `eth0` goes back to the built-in port.  Starts from the next boot. |
| `--mac aa:bb:cc:dd:ee:ff` | Only ever promote that adapter.  Handy with more than one adapter. |
| `--wait 120` | Seconds the boot hook waits for the adapter to appear. |
| `--module /path/driver.ko` | Load this driver module at boot, and move the adapter from the generic `cdc_ncm` driver over to it.  Refuses a module built for another kernel.  See [A faster driver](#a-faster-driver-for-realtek-adapters). |
| `--driver NAME` | The driver name the module registers, if it can't be read from the file.  Rarely needed. |
| `--no-watch`, `--no-module`, `--no-mac` | Turn that setting off again. |
| `--json` | With `status`, `speedtest` or `update --check`: machine-readable output.  The TV app uses it. |

The options you install with are saved in `/var/lib/webosbrew/lg-usb-2-eth0.conf`.  Run `install` again to change any of them; the ones you don't give are kept.

## How it works

At boot the Homebrew Channel runs everything in `/var/lib/webosbrew/init.d`.  The hook is a link to the script (inside the TV app, or a copy in `/home/root/lg-usb-2-eth0`), and its settings live in their own file, so updating the script never loses them.  At boot it:

1. Starts a background job and returns at once, so other startup hooks and the Homebrew Channel's failsafe timer aren't held up.
2. Loads your `--module`, if you gave one.
3. Waits up to `--wait` seconds for a USB Ethernet adapter.  A device counts only if it's wired Ethernet on the USB bus, and not Wi-Fi (a USB device on many LG TVs), a phone or a modem.
4. If none turns up, it changes nothing and the built-in port stays `eth0`.
5. With `--module`, it moves the adapter from the generic `cdc_ncm` driver to your module's driver.  If the module doesn't take it within a few seconds, it goes back to `cdc_ncm`.  Each adapter gets one try per boot.
6. It renames the built-in `eth0` to `eth2` and the adapter to `eth0`, then brings both up.  A rename that webOS interrupts is retried, and if a step still fails, the old names are put back.
7. With `--watch`, it keeps checking every few seconds and follows the adapter being plugged in or out.
8. With `--module`, it also keeps the adapter on the faster driver.  Standby resets the TV's USB ports, and the adapter comes back on `cdc_ncm`, so the hook moves it over again.  The check every few seconds only looks at a couple of `/sys` folders, so it costs next to nothing.

It logs to `/var/lib/webosbrew/lg-usb-2-eth0.log` (it starts over once it reaches 32 KB), and `status` shows the last lines.  `apply` and `revert` run detached from your SSH session, so they finish even when the session drops, and they warn you first if you're connected through a port that's about to change.

## Choosing an adapter

What decides whether this works on your TV is **whether its kernel has a driver for your adapter's chip**.  That varies by model and firmware, not just by webOS version.  The chip matters more than the brand.

- **Realtek RTL8153 (gigabit) and RTL8156 (2.5G):** the most common chips.  Newer kernels may only have the generic `cdc_ncm` driver for them, which works but is slower.
- **ASIX AX88179:** works out of the box on many older TVs.  One report of the newer AX88179A not being detected on webOS 25.
- **USB 2.0 is fine.**  Many LG TVs, the C2 included, only have USB 2.0 ports.  There you'll top out around 300 Mbit/s, still about three times the built-in port.  If your TV does have a USB 3.0 port (usually the blue one), use it for more.

Before buying, run `sh LG-USB-2-ETH0.sh status`.  It lists which USB network drivers your kernel has.  If you already have an adapter that isn't working, `status` tells you when the kernel sees it but has no driver for it.

## A faster driver for Realtek adapters

Many TVs give Realtek RTL8153 and RTL8156 adapters to the generic `cdc_ncm` driver.  It works, but it's slower and drops out under load.  The TV's own Realtek driver is often too old to recognize newer chips, and because it's built into the kernel, it can't be swapped out.  A newer Realtek driver, built for your exact kernel under a different name, fixes that.

[DonZoomik](https://github.com/DonZoomik/webos-r8152) built one, `r8152_oot` (Realtek's v2.22.1 driver), for kernel `5.4.268-329.ptl4tv.5`.  That kernel runs on at least the 2024 C4 and the 2022 C2 on webOS 25 (10.3.1, firmware 33.31.68).  If your TV runs that kernel, `status` says so, and two commands set it up:

```sh
sh LG-USB-2-ETH0.sh get-driver
sh LG-USB-2-ETH0.sh install --module /home/root/lg-usb-2-eth0/drivers/r8152_oot.ko
sh LG-USB-2-ETH0.sh apply      # optional: switch now instead of at the next reboot
```

`get-driver` only offers a module for the exact kernel it was built for.  It downloads from a fixed commit of the author's repository and keeps the file only if its SHA-256 matches.  The module comes from that project, not this one, so credit and thanks go to DonZoomik.

What LG-USB-2-ETH0 does with it:

- **Moves the adapter over.**  The kernel still picks `cdc_ncm` first, so the script releases the adapter and binds it to the new driver.  If that doesn't work within a few seconds, the adapter goes back to `cdc_ncm`.
- **Turns off scatter-gather** on the new driver.  In DonZoomik's testing, it made the TV's USB controller hang after a while.
- **Never forces anything.**  A module built for another kernel is refused before it's loaded.  Each adapter gets one try per boot, so a driver that doesn't support it can't cause repeated drops.

**Set up Wi-Fi on the TV first.**  Moving drivers takes the adapter offline for a moment, and Wi-Fi is your way back in if something goes wrong.  A reboot always undoes a live switch, and `uninstall` removes it for good.

Already using DonZoomik's `r8152-autobind.sh`?  It does the same job.  Keep only one: run `sh /home/root/r8152-autobind.sh uninstall`, then install LG-USB-2-ETH0 with `--module`.  `status` warns if both are set up.

Have a module for a different kernel?  `install --module /full/path/driver.ko` works with any USB network driver built for your exact kernel (`uname -r`).

## webOS compatibility

The script only needs root, the Homebrew Channel, `ip` and `/sys`, which every rooted webOS TV has.  It's plain POSIX `sh` and is tested under busybox `sh`, the shell on the TV.

| webOS | What people have reported | Source |
|-------|---------------------------|--------|
| webOS 3.5 / 4 (2017 and 2018: B7, C7, C8) | ASIX-based adapters (Cable Matters USB 3.0) work out of the box.  TP-Link UE300 (RTL8153) didn't work on C7 or C8.  Settings show "no connection" while apps work, which is what this script fixes. | [lgwebos.com thread](https://www.lgwebos.com/topic/3395-gigabit-ethernet-on-smart-tv/page/2/) |
| webOS 24 | Where this script was first written. | |
| webOS 25 on a 2024 C4 | RTL8153 and RTL8156 adapters come up through the generic `cdc_ncm` driver.  They work, but slower and with drops.  A community-built `r8152` module helps. | [DonZoomik/webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| webOS 25 (10.3.1, firmware 33.31.68) on a 2022 C2 (OLED65C2PUA), kernel `5.4.268-329.ptl4tv.5` | Tested by the author.  An RTL8156 adapter (`0bda:8156`) comes up on `cdc_ncm`, and LG-USB-2-ETH0 makes it `eth0`.  With `r8152_oot` from `get-driver` and `install --module`, it's confirmed through a full reboot: at startup the hook loads the driver, moves the adapter over on the first try, turns scatter-gather off and makes it `eth0`, with traffic going out the adapter.  The C2's USB port runs at USB 2.0 speed. | This repo |
| webOS 25 on 2024 QNED and OLED (Paparoa) | Reported that the Realtek driver was removed, so the adapter needs a module built for that exact kernel. | [mbenitez343/lg-webos-2024-ethernet-fix](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) |
| webOS 25 on a 2025 B5 | One report of an AX88179A not being detected at all. | [LG developer forum](https://forum.webostv.developer.lge.com/t/feature-request-usb-gigabit-ethernet-adapter-support-on-webos-25/28185) |

**Tested on your TV?**  Please [send a compatibility report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml), whether it worked or not.  Reports from real TVs are what this table needs most.

## Real speeds

Don't expect gigabit.  The TV's USB controller and CPU are the limit.  Measured on real TVs:

| Setup | Speed | Source |
|-------|-------|--------|
| Built-in port (any model) | about 95 Mbit/s | 100 Mbit/s port |
| RTL8153 on a 2024 C4 (webOS 25), generic `cdc_ncm` driver | about 200 to 255 Mbit/s, with drops | [webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| Same adapter with the community `r8152` module | about 290 to 330 Mbit/s | [webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| Cable Matters adapter on a 2018 C8 | about 250 Mbit/s | [lgwebos.com thread](https://www.lgwebos.com/topic/3395-gigabit-ethernet-on-smart-tv/page/2/) |
| RTL8156 on a 2022 C2 (webOS 25, USB 2.0) with `r8152_oot` | 272 Mbit/s down, 287 up, 7 ms | This repo, with `speedtest` |

That's still two to three times the built-in port, which is plenty for 4K remuxes.

## Troubleshooting

**Lost SSH while switching?**  The switch still finishes on the TV.  Reconnect over Wi-Fi.  The adapter has its own MAC address, so your router may give the TV a new IP.  A DHCP reservation for the adapter's MAC keeps it steady.

**Want everything back the way it was?**  `sh LG-USB-2-ETH0.sh uninstall --now`.  Or just `uninstall` and reboot.

**Wi-Fi on too?**  webOS may send traffic over Wi-Fi while it's connected, even with the adapter working.  `status` warns when that happens.  Turn Wi-Fi off in the TV's settings once the adapter works, or keep it on only as a way back in while you set things up.

**Both cables plugged in?**  Unplug the built-in one.  With two wired links up, traffic can take the slower port.

**Settings still say "Not Connected", or no IP?**  Run `status`.  If the adapter is `eth0` but has no IPv4 address, give webOS a moment, then try unplugging and replugging the network cable.

<a id="adapter-not-detected"></a>**Adapter not detected?**  `status` lists adapters the kernel sees but has no driver for.  Try an adapter with a different chip, another USB port, or a powered hub.  Run `get-driver` to see if a better driver is known for your kernel.  If someone has built a driver module for your exact kernel (`uname -r`), install with `--module /full/path/driver.ko`.  The script refuses a module built for another kernel.

**Adapter plugged in after boot, or unplugged and back?**  Without `--watch`, run `apply`, or reboot.  With `--watch`, it's handled for you.

**Something went wrong at boot?**  The hook only renames interfaces (and loads your `--module`, if you gave one), so a reboot without it always starts clean.  If the Homebrew Channel drops into failsafe mode, telnet in, run `uninstall`, and reboot.

**Still stuck?**  Run `sh LG-USB-2-ETH0.sh report` and paste the output into a [bug report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=bug-report.yml).

## FAQ

**Does it survive a firmware update?**  The hook lives in the Homebrew Channel's folder, so it stays as long as root does.  If an update removes root, the hook stops running and the TV just goes back to using the built-in port.

**Does it change my network settings?**  No.  webOS still sets up the wired connection itself.  The script only changes which device is called `eth0`.

**Does it affect Wi-Fi?**  No.  Wi-Fi modules are skipped on purpose, even the ones that sit on USB.

**What about phone tethering or a USB modem?**  Those are skipped too (`rndis_host`, `ipheth`, `cdc_mbim`, `qmi_wwan`).

**Can I use two adapters?**  Yes.  Pin the one you want with `--mac`.  Without it, the first adapter with a cable in wins.

**Does it work on non-LG webOS devices?**  It's written for LG TVs with the Homebrew Channel.  It may work elsewhere, but that isn't tested.

## Upgrading from v1

Run `sh LG-USB-2-ETH0.sh install`.  It replaces the v1 hook in place (same file name).  If you had "disabled" v1, `status` flags it: on TVs where `run-parts` is busybox's, the `.disabled` file kept running at boot.  `disable` moves it out of `init.d`, or `install` replaces it.  See the [changelog](CHANGELOG.md) for everything that changed.

## Development and tests

The test suite runs the script against a fake `/sys` and a fake `ip`, so it needs no TV and no root, and touches nothing on your machine:

```sh
tests/run.sh busybox   # busybox sh with only busybox applets on PATH, closest to the TV
tests/run.sh dash
tests/run.sh bash
tests/run.sh busybox watch   # only tests whose name contains "watch"
```

It covers swapping and reverting, Wi-Fi and tethering being left alone, MAC pinning, rename retries and rollback, the SSH session warning, the boot hook with and without an adapter, a late adapter, `--watch` hotplug, disable and enable, upgrading from v1, `--module` checks, moving an adapter to a new driver and falling back when that fails, `get-driver` refusing unknown kernels and bad checksums, keeping the faster driver after standby, the speed test, updates (refusing a bad checksum, for the app and the plain script), and the report.  A fake `curl` and `luna-send` stand in for the network and the TV's services.  CI runs ShellCheck and the whole suite under all three shells on every push.

The TV app is in `webos-app/`.  `webos-app/build.sh` builds the IPK and its Homebrew Channel manifest (it needs `ares-package` from `@webos-tools/cli`).  CI builds it on every push, and checks the issue forms too.

Releases are made by pushing a `v*` tag.  The release workflow runs the tests, checks the tag against `VERSION` in the script, builds the app, and publishes the script, `SHA256SUMS`, the IPK and its manifest.

## Contributing

Real TV reports help most: your model, webOS version, adapter chip, and the output of `report`.  Use the [compatibility report form](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml).

Pull requests are welcome.  Please keep the script POSIX `sh` (it has to run under busybox), and add or update a test in `tests/run.sh` for any change in behavior.  For security issues, see [SECURITY.md](SECURITY.md).

## Thanks

A big thank you to **[DonZoomik](https://github.com/DonZoomik)** for [webos-r8152](https://github.com/DonZoomik/webos-r8152).  He found the right kernel source in LG's open-source bundles, built Realtek's current driver for webOS 25 under its own name so it can sit beside the TV's built-in one, and tracked down the scatter-gather setting that hangs the TV's USB controller.  He also published careful benchmarks.  That work is what turns a USB adapter on these TVs from "works, but drops out" into a steady connection, and `get-driver` and `--module` are built on it.  If it helps you too, go give his repo a star.

Thanks also to the [webOS Homebrew](https://www.webosbrew.org/) project for the Homebrew Channel and the startup hooks this script relies on, and to [RootMyTV](https://rootmy.tv/) for making rooting possible.

## License

MIT.  See [LICENSE](LICENSE).

## Author

**OhMyBahGosh** ([@ohmybahgosh](https://github.com/ohmybahgosh))
