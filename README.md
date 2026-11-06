<div align="center">

# LG-USB-2-ETH0

**Make a USB Ethernet adapter the TV's `eth0` on rooted LG webOS TVs, safely and at every boot.**

[![CI](https://github.com/ohmybahgosh/LG-USB-2-ETH0/actions/workflows/ci.yml/badge.svg)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/actions/workflows/ci.yml)
[![Release](https://ohmybahgosh.dev/badges/lg-usb-2-eth0-release.svg)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest)
[![Drivers waiting for testers](assets/badge-drivers-to-test.svg)](#more-drivers-on-the-way)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Listed in awesome-webos](https://img.shields.io/badge/listed%20in-awesome--webos-fc60a8)](https://github.com/tolgakurtuluss/awesome-webos)
[![Project page](https://img.shields.io/badge/ohmybahgosh.dev-project%20page-3ddc97)](https://ohmybahgosh.dev/lg-usb-2-eth0/)
[![GitHub stars](https://ohmybahgosh.dev/badges/lg-usb-2-eth0-stars.svg)](https://github.com/ohmybahgosh/LG-USB-2-ETH0/stargazers)

<img src="assets/banner.webp" width="100%" alt="LG-USB-2-ETH0 for rooted LG webOS TVs: make a USB Ethernet adapter the TV's eth0, two to three times the built-in port, from a TV app on the remote.  Homebrew Channel app, Realtek and ASIX drivers, Wi-Fi as a backup, undo in one press.  Next to it, the app's status screen on a TV and its icon on the home screen." />

**[Get the TV app](#with-the-tv-app)** · **[Install over SSH](#over-ssh)** · **[Drivers](#drivers)** · **[Troubleshooting](#troubleshooting)** · **[Project page](https://ohmybahgosh.dev/lg-usb-2-eth0/)**

</div>

LG TVs ship with a 100 Mbit/s wired port.  A gigabit USB adapter is two to three times faster on the same TV, even on the USB 2.0 ports many models have (a 2022 C2 included).  But webOS names it `eth1`, and parts of webOS only look at `eth0`.  So the settings screen says "Not Connected" while the internet works, and some streaming apps refuse to play.

LG-USB-2-ETH0 renames the adapter to `eth0` and parks the built-in port under another name, so webOS and its apps treat the adapter as the TV's wired connection.  A small boot hook does it again at every start.  Use the TV app from the Homebrew Channel, with no SSH needed, or the same script over SSH.  It can also find, check and install a better driver for your adapter, test new ones built for your TV, and block firmware updates harder.

> [!WARNING]
> **Keep firmware updates off on a rooted TV.**  LG's current firmware, webOS 26 included, patches the known ways to root a TV.  An update may remove root for good, and this tool stops working with it.  Turn off **Automatic software updates** in the TV's settings, turn on **Block system updates** in the Homebrew Channel, and turn on **Block updates harder** in this app ([how it works](#blocking-updates)).

<details>
<summary><b>More on firmware updates and root</b></summary>

<br>

LG has started rolling out webOS 26 to 2022 to 2025 models (version 43.21.94 for the C2, 43.21.96 for the C3, C4 and C5, as of early November 2026).  Once a TV is on patched firmware, it can't be rooted again.

- Turn off **Automatic software updates** in the TV's settings (on recent models it's under Support, Software Update).
- In the Homebrew Channel, open Settings and turn on **Block system updates**.
- Turn on **Block updates harder** in the LG-USB-2-ETH0 app (or install with `--block-updates`).  It adds to the Homebrew Channel's block without touching it: see [Blocking updates](#blocking-updates).
- Some TVs still show the update prompt anyway.  Blocking LG's update servers on your router or Pi-hole stops it: see the list in [Homebrew Channel issue #96](https://github.com/webosbrew/webos-homebrew-channel/issues/96#issuecomment-2119483327).
- Not sure about your firmware?  Check it at [CanI.RootMy.TV](https://cani.rootmy.tv/).

People keep looking for new ways in.  RootMyTV, crashd, WTA, DejaVuln and faultmanager each came along after the one before it was patched, so a root method for newer firmware may well turn up, but there's no telling when.  The [webOS Homebrew rooting page](https://www.webosbrew.org/rooting/) is the place to watch.

</details>

<details>
<summary><b>How this is built: AI-assisted, tested on a real TV</b></summary>

<br>

I, [OhMyBahGosh](https://github.com/ohmybahgosh), wrote v1 by hand.  From v2.0 on, it's written with AI coding agents (Claude), directed, reviewed and tested by me.  I've been building software for over 17 years.  My day job is data engineering, and network security and pentesting are what I do for fun.  AI writes a lot of the code here; I decide what it does, check how it does it, and nothing ships until it's run on a real TV (an LG C2 on webOS 25).

The fixes that mattered most came from that real-TV testing, not from the AI: standby putting the adapter back on the slow driver, webOS quietly sending traffic over Wi-Fi instead of the adapter, and the GitHub report form opening blank on a phone.  The [changelog](CHANGELOG.md) has the full story.

- **Tests on every push:** 90 [tests](tests/run.sh) run the script against a fake `/sys` under busybox `sh` (the TV's shell), dash and bash, along with ShellCheck, a build of the TV app, and a check of the issue forms.  The CI badge above shows the latest run.
- **Checked downloads:** driver modules and updates come from fixed releases or commits and are kept only if their SHA-256 matches.  A driver is only loaded on the exact kernel it was built for, and only offered for adapters it supports.
- **Hard to break the TV:** no system files are touched, the boot hook is a link that stops running if the app is removed, every change has a fallback, and a reboot without the hook always starts clean.

The tested driver modules `get-driver` offers were built by [DonZoomik](https://github.com/DonZoomik/webos-r8152), [mbenitez343](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix), [OCT0PUSCRIME](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver), [dd3git](https://github.com/dd3git/lg-webos-ax88179-driver) and [throwaway96](https://github.com/throwaway96/webos-kernel-drivers); this script only checks and loads them.  The ones waiting for testers are built here, from LG's own kernel source ([docs/driver-build.md](docs/driver-build.md)).  Commits list me as the author and Claude as the committer, which is why they show as Verified.  Found a problem?  See [SECURITY.md](SECURITY.md) or open an issue.

</details>

## Contents

- [What it fixes](#what-it-fixes)
- [Get started](#get-started): [the TV app](#with-the-tv-app), [over SSH](#over-ssh), [is it safe?](#is-it-safe-and-how-do-i-undo-it)
- [The TV app](#the-tv-app)
- [Choosing an adapter](#choosing-an-adapter)
- [Drivers](#drivers): [known to work](#a-faster-driver), [waiting for testers](#more-drivers-on-the-way)
- [Real speeds](#real-speeds)
- [webOS compatibility](#webos-compatibility)
- [Blocking updates](#blocking-updates)
- [Troubleshooting](#troubleshooting) and [FAQ](#faq)
- [Commands and options](#commands-and-options) and [how it works](#how-it-works)
- [Upgrading from v1](#upgrading-from-v1)
- [Development and tests](#development-and-tests), [Contributing](#contributing), [Thanks](#thanks)

## What it fixes

<img src="assets/how-it-works.svg" width="100%" alt="Before: webOS and its apps use eth0, the 100 Mbit/s built-in port, and the USB adapter sits unused as eth1.  After: the USB adapter is eth0 at about 300 Mbit/s, and the built-in port is parked as eth2." />

| Problem | What you see | What this does |
|---------|--------------|----------------|
| **Streaming apps fail** | Apps like Paramount+ refuse to play over `eth1` | The adapter becomes `eth0` |
| **"Not Connected" in settings** | webOS shows no wired connection while the adapter works | Interface names match what webOS expects |
| **100 Mbit/s built-in port** | High-bitrate remuxes, Plex and Moonlight stutter | Uses the faster adapter (see [Real speeds](#real-speeds)) |
| **No driver for the adapter** | The adapter isn't detected, or sits on a slow generic driver | Finds, checks and loads a driver built for your exact kernel (see [Drivers](#drivers)) |

## Get started

You need:

- A rooted LG TV with the [Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel).  Check yours at [cani.rootmy.tv](https://cani.rootmy.tv/).
- A USB Ethernet adapter.  The chip matters more than the brand: see [Choosing an adapter](#choosing-an-adapter).
- **A Wi-Fi connection while you set this up.**  Switching takes the wired ports down for a moment, and Wi-Fi is your way back in.

### With the TV app

The easiest way, with no SSH at all.

1. Open the Homebrew Channel, go to **Settings**, and add the repository `https://ohmybahgosh.dev/repo`.
2. Install **LG-USB-2-ETH0** from the list and open it.
3. Turn on **Run at every boot**, and press **Switch now** to switch without a reboot.

The Homebrew Channel then offers updates like for any other app.

<details>
<summary>Or install the IPK yourself</summary>

<br>

Download `org.ohmybahgosh.lgusb2eth0_*.ipk` from the [latest release](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest) and install it with `ares-install`, or copy it to `/tmp` on the TV and run this, with the file name you downloaded:

```sh
luna-send -n 1 luna://com.webos.appInstallService/dev/install '{"id":"org.ohmybahgosh.lgusb2eth0","ipkUrl":"/tmp/org.ohmybahgosh.lgusb2eth0_2.4.11_all.ipk"}'
```

</details>

### Over SSH

The same thing without the app, if you'd rather see every step.  You need SSH (or telnet) access as root.  On the TV:

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

No `curl`?  Use `wget` the same way.  If both fail with a TLS error (common on older firmware), download the two files on your computer and copy them over with `scp`.  Run `sh LG-USB-2-ETH0.sh` with no arguments for a menu, and see [Commands and options](#commands-and-options) for the rest.

Already set up over SSH?  Open the app and it picks up your settings.  Its boot hook links to the copy of the script inside the app, so the app and the hook always run the same version.

<details>
<summary>What <code>status</code> looks like once it's working</summary>

```
=== LG-USB-2-ETH0 v2.4.11 status ===
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
Notes:
  - The Homebrew Channel blocks four of LG's update servers, but misses others.  install --block-updates closes the rest.
  - eth0 is on USB 2.0, which tops out around 300 Mbit/s on these TVs.
```

This sample comes from the test suite, with example TV details filled in.  Your model, firmware and driver names will differ.

</details>

### Is it safe, and how do I undo it?

It adds one boot hook, a link at `/var/lib/webosbrew/init.d/S01fix-eth`, keeps its settings in `/var/lib/webosbrew/lg-usb-2-eth0.conf`, and only renames network interfaces.  No system files are touched, and network settings only if you turn on the Wi-Fi backup or Block updates harder.  With no adapter plugged in, the hook changes nothing, and a reboot without it always starts clean.

To undo everything, press **Turn everything off** in the TV app (do this before you remove the app), or run `sh LG-USB-2-ETH0.sh uninstall --now`.

## The TV app

It runs the same script underneath, as root through the Homebrew Channel.  It works with the remote's arrows and OK, or the Magic Remote pointer.

<p align="center">
  <img src="assets/app-tv.gif" width="100%" alt="The TV app on an LG C2: scrolling the menu, opening the Wi-Fi as a backup confirmation and the Report for GitHub QR code, then back to the top" />
</p>

- **Status at a glance:** whether the adapter is `eth0`, its driver, link speed, USB bus, address, Wi-Fi, and any problems found, like a cable that only connects at 100 Mbit/s.
- **Run at every boot**, **Follow plug and unplug**, **Wi-Fi as a backup**, **Block updates harder** and **Switch now**, as on/off switches.
- **Faster driver:** only shows up when a driver is known for your TV's exact kernel and an adapter it supports is plugged in.  It downloads, checks and sets up the driver in one go.
- **Test a new driver:** only on TVs whose kernel has a driver waiting for testers.  One press downloads and checks it, loads it until the next restart, moves the adapter to it, checks it gets online, and shows a QR code that opens a filled-in test report.
- **Speed test:** download, upload and latency through the TV's current connection, against Cloudflare's nearest server.
- **Report for GitHub:** a QR code that opens a compatibility report on your phone with your TV, adapter, speed and the full report already filled in (MAC addresses hidden).
- **Updates:** tells you when a new version is out.  If you installed through the Homebrew Channel repo, the update comes from there.  Otherwise the app downloads it, checks its SHA-256, and installs it itself.  Either way, the new version opens with a short list of what's new.
- **Turn everything off:** removes the boot hook and gives `eth0` back to the built-in port.

<details>
<summary><b>Screenshots</b></summary>

<br>

<table>
  <tr>
    <td width="50%"><img src="assets/screenshots/app-home.png" alt="Status screen: USB adapter is eth0, Realtek RTL8156 on r8152_oot, 1000 Mbit/s link over USB 2.0, with switches for Run at every boot, Faster driver, Follow plug and unplug, Wi-Fi as a backup and Block updates harder" /></td>
    <td width="50%"><img src="assets/screenshots/app-speed.png" alt="Speed test result: 272 Mbit/s download, 287 Mbit/s upload, 7 ms latency, over eth0 to Cloudflare" /></td>
  </tr>
  <tr>
    <td align="center"><b>Status at a glance</b></td>
    <td align="center"><b>Speed test</b></td>
  </tr>
  <tr>
    <td width="50%"><img src="assets/screenshots/app-drvtest-offer.png" alt="A new driver to test: the app says a driver has been built for this TV's kernel from LG's own source, that it's only loaded until the next restart, and that the adapter is one it supports.  Press OK to test it now, or BACK for later." /></td>
    <td width="50%"><img src="assets/screenshots/app-drvtest-result.png" alt="Driver test: it works.  A QR code that opens a filled-in driver test report on GitHub, next to the report text: model, firmware, kernel, chip, driver, adapter, result and the link it got." /></td>
  </tr>
  <tr>
    <td align="center"><b>A new driver to test</b></td>
    <td align="center"><b>Its result, ready to send</b></td>
  </tr>
  <tr>
    <td width="50%"><img src="assets/screenshots/app-report.png" alt="Report for GitHub: a QR code that opens a filled-in compatibility report, next to the report text with MAC addresses masked" /></td>
    <td width="50%"><img src="assets/screenshots/app-update.png" alt="Update row at the top of the menu: Update to the latest version, with the version you have, downloads and installs" /></td>
  </tr>
  <tr>
    <td align="center"><b>Report for GitHub</b></td>
    <td align="center"><b>Updates</b></td>
  </tr>
</table>

<sub>The recording above is from a real LG C2.  The screenshots use made-up data from <a href="scripts/screenshots/">scripts/screenshots</a>, matching a C2 with an RTL8156 adapter.</sub>

</details>

## Choosing an adapter

What decides whether this works on your TV is **whether its kernel has a driver for your adapter's chip**.  That varies by model and firmware, not just by webOS version.  The chip matters more than the brand.

- **Realtek RTL8153 (gigabit) and RTL8156 (2.5G):** the most common chips.  Newer kernels may only have the generic `cdc_ncm` driver for them, which works but is slower, and some models have no Realtek driver at all.  `get-driver` may offer a better one, or `test-driver` a new one: see [Drivers](#drivers).
- **ASIX AX88179:** works out of the box on many TVs, using the TV's own `ax88179_178a` driver, like a 2024 G4 on webOS 25 ([#2](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/2)).  Where the kernel has no ASIX driver, there's often one to get or test.
- **USB 2.0 is fine.**  Many LG TVs, the C2 included, only have USB 2.0 ports.  There you'll top out around 300 Mbit/s, still about three times the built-in port.  If your TV does have a USB 3.0 port (usually the blue one), use it for more.

Before buying, run `sh LG-USB-2-ETH0.sh status`: it lists which USB network drivers your kernel has.  The [firmware audit](docs/firmware-audit.md) lists them too, read straight from LG's firmware.  If you already have an adapter that isn't working, `status` tells you when the kernel sees it but has no driver for it.

### Tested adapters

Adapters confirmed on a real TV.  Plain links: no affiliate codes, no sponsorship, nobody paid for a spot here.

| Adapter | Chip | Tested on | Result |
|---------|------|-----------|--------|
| [UGREEN USB-C to 2.5G Ethernet (Amazon)](https://www.amazon.com/dp/B0CD1FDKT1) | Realtek RTL8156BG (`0bda:8156`) | 2022 C2, webOS 25, USB 2.0 port | Works.  272 Mbit/s down, 287 up with `r8152_oot` (it's on `cdc_ncm` without it) |
| TP-Link UE306 V1.6 ([discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3)) | ASIX AX88179 (`0b95:1790`) | 2020 UN7300 (55UN7300PUF), webOS 5, USB 2.0 port | Works with OCT0PUSCRIME's `ax88179_178a` build from `get-driver`, since that kernel has no ASIX driver.  228 Mbit/s down, 325 up |
| ASIX AX88179 adapter ([#2](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/2)) | ASIX AX88179/178A (`0b95:1790`) | 2024 G4 (OLED65G48LW), webOS 25, USB 2.0 port | Works out of the box on the TV's own `ax88179_178a` driver.  292 Mbit/s down, 51 up |

Got another adapter working?  [Send a compatibility report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml) (the TV app makes one for you) and it'll be added here.

<details>
<summary>A note on the UGREEN, and Realtek adapters with a USB-A plug</summary>

<br>

The UGREEN has a USB-C plug and LG TVs have USB-A ports, so on the author's C2 it goes through a small USB-C (female) to USB-A (male) converter ([this 4-pack on Amazon](https://www.amazon.com/dp/B0BJ8YQ2LM)).  It works, but it's just what was on hand.  Those converters are USB 2.0, which is all the C2's port can do anyway, but on a TV with a USB 3.0 port they'd hold the adapter back.  If you're buying, get one with a USB-A plug and skip the converter.

These use the same RTL8156BG chip as the UGREEN, so they should work the same way: on `cdc_ncm` out of the box, and faster with `r8152_oot` where `get-driver` offers it.  None has been tested on a TV yet, so a report helps.

| Adapter | Chip | Plug |
|---------|------|------|
| [UGREEN USB to 2.5G Ethernet, model 25051 (Amazon)](https://www.amazon.com/dp/B0CWV2Q6HJ) | RTL8156BG | USB-A, USB 3.0.  The USB-A version of the UGREEN above. |
| [Cable Matters USB to 2.5Gb Ethernet, model 202485 (Amazon)](https://www.amazon.com/dp/B0GFHS6L87) | RTL8156BG | USB-A, USB 3.0 |
| [SABRENT USB-A to 2.5Gbps Ethernet, NT-UA25 (Amazon)](https://www.amazon.com/dp/B0FMBXSNKL) | RTL8156BG | USB-A, USB 3.0 |

Same deal: plain links, no affiliate codes.  Check the listing says RTL8156B or RTL8156BG before you buy, since sellers sometimes change parts.

</details>

## Drivers

A driver module built for your exact kernel helps in two cases:

- **The adapter is on a slow generic driver.**  Many TVs give Realtek RTL8153 and RTL8156 adapters to `cdc_ncm`.  It works, but it's slower and drops out under load.  The TV's own Realtek driver is often too old to recognize newer chips, and because it's built into the kernel, it can't be swapped out.  A newer Realtek driver under a different name fixes that.
- **The kernel has no driver for the chip at all.**  LG left the Realtek driver out of many recent kernels, and some have no ASIX driver.  There the adapter isn't detected until a module adds one.

There are two kinds: drivers known to work, which **Faster driver** (`get-driver`) sets up, and new drivers waiting for someone with that TV to try them, which **Test a new driver** (`test-driver`) tries.

### A faster driver

These are known to work on a real TV.  Most are built for one exact kernel, and a few for one chip.  `status` says when one fits your TV.

| Driver | For | Built by |
|--------|-----|----------|
| `r8152_oot` (Realtek v2.22.1) | Kernel `5.4.268-329.ptl4tv.5` on webOS 25: the 2022 C2, 2023 C3 and UR9000, and 2024 C4 and G4.  RTL8153 and RTL8156 adapters. | [DonZoomik](https://github.com/DonZoomik/webos-r8152) |
| `r8152` (v1.10.11) | 2024 QNED and OLED on webOS 25, where LG removed the Realtek driver, on kernel `5.4.268-294.17.paparoa.pine.2`.  Gigabit RTL8152 and RTL8153 adapters, not 2.5G ones. | [mbenitez343](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) |
| `ax88179_178a` (ASIX v1.19.0) | 2020 TVs on webOS 5 (UN7300, kernel `4.4.84-612.jcl4tv.40`), which have no ASIX driver.  Tested with a TP-Link UE306 ([discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3)). | [OCT0PUSCRIME](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver) |
| `ax88179_178a` (from LG's source) | Kernel `5.4.268-294.24.papikonda.2` on webOS 25: the 2025 B5, and the 2024 B4 and QNED85, none of which has an AX88179 driver.  Tested by its author on a B5. | [dd3git](https://github.com/dd3git/lg-webos-ax88179-driver) |
| `r8152`, `ax88179_178a` | TVs with the Realtek K5Lp chip on kernel 4.4.84, picked by chip.  Gigabit Realtek and ASIX adapters.  Not yet tested with this app. | [throwaway96](https://github.com/throwaway96/webos-kernel-drivers) |

In the TV app it's one switch: **Faster driver**.  Over SSH, two commands, with the file `get-driver` downloaded (`r8152_oot.ko`, `r8152.ko` or `ax88179_178a.ko`):

```sh
sh LG-USB-2-ETH0.sh get-driver
sh LG-USB-2-ETH0.sh install --module /home/root/lg-usb-2-eth0/drivers/r8152_oot.ko
sh LG-USB-2-ETH0.sh apply      # optional: switch now instead of at the next reboot
```

**Set up Wi-Fi on the TV first.**  Moving drivers takes the adapter offline for a moment, and Wi-Fi is your way back in if something goes wrong.  A reboot always undoes a live switch, and `uninstall` removes it for good.

<details>
<summary>How drivers are checked and set up</summary>

<br>

`get-driver` only offers a module for the exact kernel it was built for, and only when an adapter it supports is plugged in (it checks the adapter's USB ID against the module's own list).  Drivers built per chip check the chip name too (`nyx-cmd DeviceInfo query device_name`).  Some modules name only the base kernel version inside (like `5.4.268`), which the TV accepts.  The script allows that only for a file whose SHA-256 is pinned for your exact kernel, and keeps the strict check for any other `--module`.  It downloads from a fixed commit of the author's repository and keeps the file only if its SHA-256 matches.  If that repository ever goes away, it falls back to a byte-for-byte copy in [lg-webos-usb-drivers](https://github.com/ohmybahgosh/lg-webos-usb-drivers), with the same check.

Then LG-USB-2-ETH0:

- **Moves the adapter over.**  The kernel may give the adapter to a generic driver first (`cdc_ncm`, or `cdc_ether` on TVs with no Realtek driver), so the script releases it and binds it to the new driver.  An adapter with no driver at all just picks up the new one.  If that doesn't work within a few seconds, the adapter goes back where it was.  Only adapters the module lists as supported are moved, so a phone tethered over USB is never touched.
- **Turns off scatter-gather** on Realtek's driver.  In DonZoomik's testing, it made the TV's USB controller hang after a while.
- **Never forces anything.**  A module built for another kernel is refused before it's loaded.  Each adapter gets one try per boot, so a driver that doesn't support it can't cause repeated drops.

Already using DonZoomik's `r8152-autobind.sh`?  It does the same job.  Keep only one: run `sh /home/root/r8152-autobind.sh uninstall`, then install LG-USB-2-ETH0 with `--module`.  `status` warns if both are set up.

Have a module for a different kernel?  `install --module /full/path/driver.ko` works with any USB network driver built for your exact kernel (`uname -r`).

</details>

### More drivers on the way

**102 more drivers are built and waiting for testers.**  They're built from LG's own kernel source with each TV's own config, the same way DonZoomik built his, and checked: the exact kernel version, and every symbol they use is in the TV's kernel.  None has run on a TV yet.  Once someone with that TV reports one working, it moves to **Faster driver** for everyone with that kernel.

| Kernel (`uname -r`) | TVs | Drivers |
|---|---|---|
| `5.4.268-329.ptl4tv.2` | 2022 to 2025 OLEDs on firmware 33.20 to 33.23 | Realtek |
| `5.4.268-320` | OLEDs on webOS 24 firmware 23.20 to 23.25 | Realtek |
| `5.4.96-307` | 2022 and 2023 OLEDs on firmware 03.31, 03.33 and 13.30 | Realtek |
| `5.4.268-294.*` (papikonda, ptl4tv, paparoa) | webOS 25 TVs with Realtek chips, like the B4 and B5 | Realtek and ASIX |
| `5.4.268-223.*` and `5.4.96-223.*` | webOS 24 TVs with Realtek chips, including 2022 A2 and B2 OLEDs updated to webOS 24 | Realtek and ASIX |
| `5.4.96-132.*` | webOS 23 TVs with K8 chips | Realtek and ASIX |
| `5.4.96-115.*` | webOS 22 TVs with K8 chips, like the 2022 NANO75 | Realtek and ASIX |
| `4.4.84-612.*` | 2020 TVs with the K6Lp or K6Hp chip, like the UN7300 and NANO87 | Realtek and ASIX |

On Realtek-chip TVs, one kernel name runs on several chips with different configs, so there's a build per chip, and `test-driver` picks yours.  How they're built: [docs/driver-build.md](docs/driver-build.md).

<details>
<summary><b>All 102 drivers: 29 kernels, 13 Realtek chips and LG's own chips, from webOS 5 to webOS 25</b></summary>

<br>

Each chip links to its folder in [lg-webos-usb-drivers](https://github.com/ohmybahgosh/lg-webos-usb-drivers#experimental-waiting-for-testers), with the modules, their SHA-256 and how each was built and checked.  Realtek is `r8152_oot` (RTL8152, RTL8153 and RTL8156), plus the kernel's own `r8152` (RTL8152, RTL8153) on 4.4 kernels.  ASIX is `ax88179_178a` (AX88179, AX88178A).

<!-- drivers:start -->

**webOS 25**

| Kernel (`uname -r`) | Chips | Realtek | ASIX |
|---|---|:-:|:-:|
| `5.4.268-329.ptl4tv.2` | [LG chips](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-329.ptl4tv.2) | yes |  |
| `5.4.268-294.ptl4tv.24` | [K24N](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.ptl4tv.24-k24n), [K25Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.ptl4tv.24-k25lp) | yes | yes |
| `5.4.268-294.24.papikonda.2` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k24), [K24N](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k24n), [K25Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k25lp), [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k8hp), [K8Hpp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k8hpp), [K8LpN](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k8lpn), [K8LpN2](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.24.papikonda.2-k8lpn2) | yes |  |
| `5.4.268-294.17.paparoa.pine.2` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.17.paparoa.pine.2-k24), [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.17.paparoa.pine.2-k8hp), [K8Hpp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.17.paparoa.pine.2-k8hpp), [K8LpN](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.17.paparoa.pine.2-k8lpn), [K8LpN2](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.17.paparoa.pine.2-k8lpn2) | yes | yes |
| `5.4.268-294.15.paparoa.4` | [K24N](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.15.paparoa.4-k24n), [K25Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.15.paparoa.4-k25lp) | yes | yes |
| `5.4.268-294.15.paparoa.3` | [K24N](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-294.15.paparoa.3-k24n) | yes | yes |

**webOS 24**

| Kernel (`uname -r`) | Chips | Realtek | ASIX |
|---|---|:-:|:-:|
| `5.4.96-223.obr4tv.29` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-223.obr4tv.29-k24) | yes | yes |
| `5.4.96-223.9.oeta.2` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-223.9.oeta.2-k24), [K8LpN2](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-223.9.oeta.2-k8lpn2) | yes | yes |
| `5.4.96-223.29.1.okapi.2` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-223.29.1.okapi.2-k24) | yes | yes |
| `5.4.268-320` | [LG chips](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-320) | yes |  |
| `5.4.268-223.obr4tv.42` | [K8HpT](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.obr4tv.42-k8hpt) | yes | yes |
| `5.4.268-223.42.okapi.nmrm.2` | [K24T](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.42.okapi.nmrm.2-k24t) | yes | yes |
| `5.4.268-223.29.okapi.pine.4` | [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.29.okapi.pine.4-k8hp), [K8LpN](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.29.okapi.pine.4-k8lpn), [K8Hpp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.29.okapi.pine.4-k8hpp) | yes | yes |
| `5.4.268-223.29.okapi.5` | [K24](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.29.okapi.5-k24), [K8LpN2](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.268-223.29.okapi.5-k8lpn2) | yes | yes |

**webOS 23**

| Kernel (`uname -r`) | Chips | Realtek | ASIX |
|---|---|:-:|:-:|
| `5.4.96-307` | [LG chips](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-307) | yes |  |
| `5.4.96-132.50.namtok.2` | [K8Hpp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-132.50.namtok.2-k8hpp), [K8LpN](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-132.50.namtok.2-k8lpn) | yes | yes |
| `5.4.96-132.40.nameri.pine.1` | [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-132.40.nameri.pine.1-k8hp) | yes | yes |
| `5.4.96-132.40.nameri.2` | [K8Hpp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-132.40.nameri.2-k8hpp), [K8LpN](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-132.40.nameri.2-k8lpn) | yes | yes |

**webOS 22**

| Kernel (`uname -r`) | Chips | Realtek | ASIX |
|---|---|:-:|:-:|
| `5.4.96-115.9.marine.1` | [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.9.marine.1-k8lp) | yes | yes |
| `5.4.96-115.30.mole.2` | [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.30.mole.2-k8hp), [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.30.mole.2-k8lp), [K8Ap](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.30.mole.2-k8ap) | yes | yes |
| `5.4.96-115.28.mirima.1` | [K8Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.28.mirima.1-k8hp), [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.28.mirima.1-k8lp), [K8Ap](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.28.mirima.1-k8ap) | yes | yes |
| `5.4.96-115.28.1.22.mirima.2` | [K8Ap](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.28.1.22.mirima.2-k8ap) | yes | yes |
| `5.4.96-115.22.meru.2` | [K8HpT](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.22.meru.2-k8hpt), [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.22.meru.2-k8lp) | yes | yes |
| `5.4.96-115.16.mebbin.2` | [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.16.mebbin.2-k8lp) | yes | yes |
| `5.4.96-115.16.mebbin.1` | [K8Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/5.4.96-115.16.mebbin.1-k8lp) | yes | yes |

**webOS 5**

| Kernel (`uname -r`) | Chips | Realtek | ASIX |
|---|---|:-:|:-:|
| `4.4.84-612.jcl4tv.40` | [K6Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.jcl4tv.40-k6lp) | yes |  |
| `4.4.84-612.40.jimna.1` | [K6Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.40.jimna.1-k6lp), [K6Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.40.jimna.1-k6hp) | yes | yes |
| `4.4.84-612.21.6.jardine.2` | [K6Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.21.6.jardine.2-k6lp), [K6Hp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-612.21.6.jardine.2-k6hp) | yes | yes |
| `4.4.84-611.japoon.14` | [K6Lp](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental/4.4.84-611.japoon.14-k6lp) | yes | yes |

<!-- drivers:end -->

</details>

**Help test one.**  If your TV runs one of those kernels, the app shows a **Test a new driver** row, or run:

```sh
sh LG-USB-2-ETH0.sh test-driver
```

It picks the driver for your kernel, chip and adapter, downloads it and checks its SHA-256, loads it until the next restart only, moves the adapter to it, checks it gets online, and shows a report to send (a QR code in the app).  If the TV freezes or restarts, restart it and open the app (or run `test-driver --last`) to send that result too.  Nothing loads the driver again by itself.

## Real speeds

Don't expect gigabit.  The TV's USB port is the limit.  On a C2 at full speed, the busiest CPU core was only about a third busy, so tweaks like spreading network work over more cores or bigger buffers don't help.  Two to three times the built-in port is still plenty for 4K remuxes.

<img src="assets/speeds.svg" width="100%" alt="Bar chart of measured speeds in Mbit/s: built-in port about 95; RTL8153 on the generic cdc_ncm driver 200 to 255; the same adapter with the r8152 module 290 to 330; RTL8156 on a C2 over USB 2.0 with r8152_oot 272 down and 287 up; ASIX AX88179 on a 2024 G4 with its own driver 292 down and 51 up; ASIX AX88179 on a 2020 UN7300 with OCT0PUSCRIME's driver 228 down and 325 up." />

<details>
<summary>Where these numbers come from</summary>

<br>

| Setup | Speed | Source |
|-------|-------|--------|
| Built-in port (any model) | about 95 Mbit/s | 100 Mbit/s port |
| RTL8153 on a 2024 C4 (webOS 25), generic `cdc_ncm` driver | about 200 to 255 Mbit/s, with drops | [webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| Same adapter with the community `r8152` module | about 290 to 330 Mbit/s | [webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| Cable Matters adapter on a 2018 C8 | about 250 Mbit/s | [lgwebos.com thread](https://www.lgwebos.com/topic/3395-gigabit-ethernet-on-smart-tv/page/2/) |
| RTL8156 on a 2022 C2 (webOS 25, USB 2.0) with `r8152_oot` | 272 Mbit/s down, 287 up, 7 ms | This repo, with `speedtest` |
| AX88179 on a 2024 G4 (webOS 25, USB 2.0), the TV's own driver | 292 Mbit/s down, 51 up | [#2](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/2) |
| TP-Link UE306 (AX88179) on a 2020 UN7300 (webOS 5, USB 2.0) with OCT0PUSCRIME's driver | 228 Mbit/s down, 325 up, 14 ms | [Discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3) |

</details>

## webOS compatibility

The script only needs root, the Homebrew Channel, `ip` and `/sys`, which every rooted webOS TV has.  It's plain POSIX `sh` and is tested under busybox `sh`, the shell on the TV.  What decides how well it works is the adapter's driver: the [firmware audit](docs/firmware-audit.md) reads which drivers each kernel has straight from LG's firmware, for models from 2019 to 2025, webOS 26 included.

| webOS | What people have reported | Source |
|-------|---------------------------|--------|
| webOS 3.5 / 4 (2017 and 2018: B7, C7, C8) | ASIX-based adapters (Cable Matters USB 3.0) work out of the box.  TP-Link UE300 (RTL8153) didn't work on C7 or C8.  Settings show "no connection" while apps work, which is what this script fixes. | [lgwebos.com thread](https://www.lgwebos.com/topic/3395-gigabit-ethernet-on-smart-tv/page/2/) |
| webOS 5 (5.5.0) on a 2020 UN7300 (55UN7300PUF), kernel `4.4.84-612.jcl4tv.40` | No ASIX driver in the kernel.  A TP-Link UE306 (AX88179, `0b95:1790`) works with OCT0PUSCRIME's `ax88179_178a` build, which `get-driver` offers, and LG-USB-2-ETH0 makes it `eth0`.  228 Mbit/s down, 325 up over USB 2.0. | [Discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3), [OCT0PUSCRIME/lg-webos-ax88179-driver](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver) |
| webOS 24 | Where this script was first written. | |
| webOS 25 on a 2024 C4 (same kernel as the C2 below) | RTL8153 and RTL8156 adapters come up through the generic `cdc_ncm` driver.  They work, but slower and with drops.  DonZoomik's `r8152_oot`, which `get-driver` offers, fixes that. | [DonZoomik/webos-r8152](https://github.com/DonZoomik/webos-r8152) |
| webOS 25 (10.3.1, firmware 33.31.68) on a 2022 C2 (OLED65C2PUA), kernel `5.4.268-329.ptl4tv.5` | Tested by the author.  An RTL8156 adapter (`0bda:8156`) comes up on `cdc_ncm`, and LG-USB-2-ETH0 makes it `eth0`.  With `r8152_oot` from `get-driver` and `install --module`, it's confirmed through a full reboot: at startup the hook loads the driver, moves the adapter over on the first try, turns scatter-gather off and makes it `eth0`, with traffic going out the adapter.  The C2's USB port runs at USB 2.0 speed. | This repo |
| webOS 25 on 2024 QNED and OLED (Paparoa), kernel `5.4.268-294.17.paparoa.pine.2` | The Realtek driver was removed.  A gigabit RTL8153 adapter works with mbenitez343's `r8152` build (stable on a QNED86, per its author), which `get-driver` offers.  Builds for RTL8156 and ASIX are [waiting for testers](#more-drivers-on-the-way).  Current firmware (33.31.75) moves these TVs to kernel `5.4.268-294.24.papikonda.2`: see the [firmware audit](docs/firmware-audit.md).  Not yet tested with LG-USB-2-ETH0, so a report helps. | [mbenitez343/lg-webos-2024-ethernet-fix](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) |
| webOS 25 (10.3.1, firmware 33.31.68) on a 2024 G4 (OLED65G48LW), kernel `5.4.268-329.ptl4tv.5` | An ASIX AX88179 adapter (`0b95:1790`) works out of the box on the TV's own `ax88179_178a` driver, and LG-USB-2-ETH0 makes it `eth0`.  Settings show the wired connection and apps play.  292 Mbit/s down over USB 2.0. | [#2](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/2) |
| webOS 25 on a 2025 B5 (OLED55B56LA), kernel `5.4.268-294.24.papikonda.2` | No ASIX driver: an AX88179A wasn't detected at all.  dd3git's `ax88179_178a` build fixes that, and `get-driver` offers it.  A Realtek build is [waiting for testers](#more-drivers-on-the-way).  Not yet tested with LG-USB-2-ETH0, so a report helps. | [LG developer forum](https://forum.webostv.developer.lge.com/t/feature-request-usb-gigabit-ethernet-adapter-support-on-webos-25/28185), [dd3git/lg-webos-ax88179-driver](https://github.com/dd3git/lg-webos-ax88179-driver) |

**Tested on your TV?**  Please [send a compatibility report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml), whether it worked or not.  Reports from real TVs are what this table needs most.

## Blocking updates

A firmware update can remove root, and current firmware can't be rooted again (see the warning at the top).  The Homebrew Channel's **Block system updates** is the first line: it points four of LG's update servers at nothing in `/etc/hosts`.  People in [Homebrew Channel issue #96](https://github.com/webosbrew/webos-homebrew-channel/issues/96) found what it misses, and **Block updates harder** (`--block-updates`) adds that on top.  It does this right away and again at every boot, and turning it off undoes all of it.  Tested on a C2 with webOS 25.

<details>
<summary>What it blocks, and how</summary>

<br>

- **webOS's own update check, turned off.**  A hidden webOS setting (`softwareUpdateEnable` in the `support` category) stops the updater's check, including the one it makes early in boot, before the Homebrew Channel's block is in place.  It's the same switch [Homebrew Channel PR #264](https://github.com/webosbrew/webos-homebrew-channel/pull/264) turns off.
- **The update servers the block misses**, added to `/etc/hosts`: `nsu.lge.com` (LG's current update server, which a TV still reached with the block on), `snu-dev.lge.com` and `ngfts.lge.com`.  If the Homebrew Channel's block is off, it adds that block's four servers too (`snu.lge.com`, `su.lge.com`, `su-ssl.lge.com`, `su-dev.lge.com`), the same way it does: in a writable copy of `/etc/hosts` that's gone after a reboot.  It only adds the ones that aren't there yet, in lines marked as its own, and never changes the Homebrew Channel's.
- **The server the updater reaches by IP** (`156.147.69.32`), which no hosts file can block, with one firewall rule.
- **Update details already found or downloaded** (in `/mnt/lg/cmn_data/swupdate`), deleted, so a waiting prompt goes away.

Turning it off puts the update check back how it was and takes its hosts lines and firewall rule off.  The Homebrew Channel's own setting stays as you left it either way.  With both on, they cover the same servers, which does no harm.  `status` points out when nothing blocks updates, or when only the Homebrew Channel's block does.

It doesn't touch webOS's update service itself.  Overriding that, as some people in the issue have, goes deeper into the system than this script should.  If you can, also block the servers above on your router or Pi-hole: that covers the TV before it has even started.

</details>

## Troubleshooting

**Lost SSH while switching?**  The switch still finishes on the TV.  Reconnect over Wi-Fi.  The adapter has its own MAC address, so your router may give the TV a new IP.  A DHCP reservation for the adapter's MAC keeps it steady.

**Want everything back the way it was?**  `sh LG-USB-2-ETH0.sh uninstall --now`.  Or just `uninstall` and reboot.

**Wi-Fi on too?**  webOS may send traffic over Wi-Fi while it's connected, even with the adapter working.  `status` warns when that happens.  Turn Wi-Fi off in the TV's settings once the adapter works, or keep it on only as a way back in while you set things up.  To have Wi-Fi as a backup without it taking over, turn it off and use `--wifi-fallback`.

**Link only 100 Mbit/s?**  `status` and the app flag it.  The adapter connected to your router or switch at 100 Mbit/s, so it's no faster than the built-in port.  It's usually the cable: flat and older cables often have only two of the four wire pairs.  Try a Cat5e or better cable, another port, or check the router's port speed.

**Both cables plugged in?**  Unplug the built-in one.  With two wired links up, traffic can take the slower port.

**Settings still say "Not Connected", or no IP?**  Run `status`.  If the adapter is `eth0` but has no IPv4 address, give webOS a moment, then try unplugging and replugging the network cable.

<a id="adapter-not-detected"></a>**Adapter not detected?**  `status` lists adapters the kernel sees but has no driver for.  Run `get-driver` to see if a driver is known for your kernel, or `test-driver` for one waiting for testers.  Otherwise try an adapter with a different chip, another USB port, or a powered hub.  If someone has built a driver module for your exact kernel (`uname -r`), install with `--module /full/path/driver.ko`.  The script refuses a module built for another kernel.

**Adapter plugged in after boot, or unplugged and back?**  Without `--watch`, run `apply`, or reboot.  With `--watch`, it's handled for you.

**No connection after waking from standby?**  Fixed in 2.4.2.  Before that, with `--module` (the faster driver), the adapter could be moved back to it while webOS was still reconnecting, and webOS then showed no connection until a reboot.  Update, and the log in `/var/lib/webosbrew/lg-usb-2-eth0.log` shows what happened after each standby.

**Something went wrong at boot?**  The hook only renames interfaces (and loads your `--module`, if you gave one), so a reboot without it always starts clean.  If the Homebrew Channel drops into failsafe mode, telnet in, run `uninstall`, and reboot.

**Still stuck?**  Ask in [Discussions > Q&A](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/new?category=q-a).  If something's broken, run `sh LG-USB-2-ETH0.sh report` and paste the output into a [bug report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=bug-report.yml).  [SUPPORT.md](.github/SUPPORT.md) lists where everything goes.

## FAQ

**Does it survive a firmware update?**  The hook lives in the Homebrew Channel's folder, so it stays as long as root does.  If an update removes root, the hook stops running and the TV just goes back to using the built-in port.  Current firmware, webOS 26 included, can't be rooted again, so keep updates off: see the warning at the top.

**Does it change my network settings?**  No.  webOS still sets up the wired connection itself.  The script only changes which device is called `eth0`.  The one exception is `--wifi-fallback`, if you turn it on: it flips the Wi-Fi switch on when the cable stops working, and back off when it works again.  `--block-updates` doesn't change your network either, but it does add LG's update servers to `/etc/hosts` and one firewall rule, so firmware updates can't get through.

**Does it affect Wi-Fi?**  No, unless you turn on `--wifi-fallback`.  Wi-Fi modules are never renamed or moved, even the ones that sit on USB.

**What about phone tethering or a USB modem?**  Those are skipped too (`rndis_host`, `ipheth`, `cdc_mbim`, `qmi_wwan`).

**Can I use two adapters?**  Yes.  Pin the one you want with `--mac`.  Without it, the first adapter with a cable in wins.

**My TV needs a driver nobody has built yet.  Can you build one?**  Maybe: [open an issue](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new/choose) with your TV model, firmware version, `uname -r` and adapter.  The app's **Report for GitHub** button grabs most of that.  [docs/driver-build.md](docs/driver-build.md) shows how it's done.

**Does it work on non-LG webOS devices?**  It's written for LG TVs with the Homebrew Channel.  It may work elsewhere, but that isn't tested.

## Commands and options

| Command | What it does |
|---------|--------------|
| `install` | Writes the boot hook.  Add `--now` to switch right away too. |
| `uninstall` | Removes the boot hook.  Add `--now` to give `eth0` back to the built-in port right away. |
| `apply` | Swaps the adapter in now, without touching the hook. |
| `revert` | Gives `eth0` back to the built-in port now.  (`reset` works too.) |
| `disable` / `enable` | Keeps the hook but stops it running at boot, or turns it back on. |
| `status` / `doctor` | Read-only report and checks.  Safe to run any time. |
| `report` | Short, paste-ready report for a GitHub issue: TV, chip, kernel, the USB network drivers built into it, interfaces and settings.  MAC addresses are masked. |
| `get-driver` | Downloads a driver module known to work on your exact kernel, if there is one, and checks its checksum.  With `--file PATH`, checks and uses a copy you downloaded yourself.  See [A faster driver](#a-faster-driver). |
| `test-driver` | Tries a new driver built for your exact kernel that hasn't run on a TV yet, if there is one: downloads and checks it, loads it until the next restart only, moves the adapter to it, checks it gets online, and shows a report to send.  `--last` shows the last test's report again, including after a test that froze the TV.  See [More drivers on the way](#more-drivers-on-the-way). |
| `speedtest` | Latency, download and upload through the TV's current connection, against Cloudflare's nearest server.  Four streams for about six seconds each way, so it uses a few hundred MB.  The last result shows up in `report` and the app. |
| `update` | Checks for a newer release and installs it, after checking its SHA-256.  `--check` only checks.  Inside the app, it updates the whole app.  On its own, the script replaces itself (and the boot hook's copy).  Your settings stay. |

<details>
<summary><b>Options</b></summary>

<br>

| Option | What it does |
|--------|--------------|
| `-y`, `--yes` | Answer yes to every question. |
| `--now` | With `install` or `uninstall`, also switch right away. |
| `--watch` | Keep watching after boot.  Plug the adapter in and it becomes `eth0`; unplug it and `eth0` goes back to the built-in port.  Starts from the next boot. |
| `--mac aa:bb:cc:dd:ee:ff` | Only ever promote that adapter.  Handy with more than one adapter. |
| `--wait 120` | Seconds the boot hook waits for the adapter to appear. |
| `--module /path/driver.ko` | Load this driver module at boot.  An adapter with no driver gets it right away, and one the kernel gave to a generic driver (`cdc_ncm` or `cdc_ether`) is moved over to it.  Refuses a module built for another kernel.  See [A faster driver](#a-faster-driver). |
| `--driver NAME` | The driver name the module registers, if it can't be read from the file.  Rarely needed. |
| `--wifi-fallback` | Wi-Fi as a backup.  If `eth0` loses its cable link for a minute while Wi-Fi is off, turn Wi-Fi on, so the TV joins a network it already knows.  Once the cable works again for 30 seconds, turn Wi-Fi back off, so traffic returns to the adapter.  It only turns Wi-Fi off if it turned it on.  Starts from the next boot. |
| `--block-updates` | Block firmware updates more thoroughly, on top of the Homebrew Channel's own block.  See [Blocking updates](#blocking-updates).  Starts right away, and again at every boot. |
| `--no-watch`, `--no-module`, `--no-mac`, `--no-wifi-fallback`, `--no-block-updates` | Turn that setting off again. |
| `--json` | With `status`, `speedtest` or `update --check`: machine-readable output.  The TV app uses it. |

The options you install with are saved in `/var/lib/webosbrew/lg-usb-2-eth0.conf`.  Run `install` again to change any of them; the ones you don't give are kept.

</details>

### How it works

At boot the Homebrew Channel runs everything in `/var/lib/webosbrew/init.d`.  The hook is a link to the script (inside the TV app, or a copy in `/home/root/lg-usb-2-eth0`), and its settings live in their own file, so updating the script never loses them.  It logs to `/var/lib/webosbrew/lg-usb-2-eth0.log` (it starts over once it reaches 32 KB), and `status` shows the last lines.

<details>
<summary><b>What happens at boot, step by step</b></summary>

<br>

1. Starts a background job and returns at once, so other startup hooks and the Homebrew Channel's failsafe timer aren't held up.
2. Loads your `--module`, if you gave one.
3. Waits up to `--wait` seconds for a USB Ethernet adapter.  A device counts only if it's wired Ethernet on the USB bus, and not Wi-Fi (a USB device on many LG TVs), a phone or a modem.
4. If none turns up, it changes nothing and the built-in port stays `eth0`.
5. With `--module`, an adapter that had no driver picks up your module as soon as it loads.  One the kernel gave to a generic driver (`cdc_ncm` or `cdc_ether`) is moved over to your module's driver.  If the module doesn't take it within a few seconds, it goes back where it was.  Each adapter gets one try per boot.
6. It renames the built-in `eth0` to `eth2` and the adapter to `eth0`, then brings both up.  A rename that webOS interrupts is retried, and if a step still fails, the old names are put back.
7. With `--watch`, it keeps checking every few seconds and follows the adapter being plugged in or out.
8. With `--module`, it also keeps the adapter on the faster driver.  Standby resets the TV's USB ports, and a Realtek adapter comes back on `cdc_ncm`, so the hook moves it over again.  It first lets webOS reconnect the network, then checks webOS reconnects it after the move.  If not, it takes the link down and up, and if that doesn't help, gives the adapter back to `cdc_ncm` until the next boot, so you're never left without a connection.  The check every few seconds only looks at a couple of `/sys` folders, so it costs next to nothing.
9. With `--wifi-fallback`, it checks whether `eth0` still has a cable link (one `/sys` file).  After a minute without one, if Wi-Fi is off, it turns Wi-Fi on through webOS's own connection manager, the same switch as in the TV's settings, and turns it off again once the cable has worked for 30 seconds.  It remembers turning Wi-Fi on in `/var/lib/webosbrew/lg-usb-2-eth0.wifi`, so that still happens after a reboot in between.
10. With `--block-updates`, before anything else, it turns webOS's own update check off and blocks LG's update servers again (see [Blocking updates](#blocking-updates)), since the hosts entries and firewall rule don't survive a reboot.

`apply` and `revert` run detached from your SSH session, so they finish even when the session drops, and they warn you first if you're connected through a port that's about to change.

</details>

## Upgrading from v1

**With the TV app, no SSH needed.**  Install the app ([see above](#with-the-tv-app)) and open it.  It finds your v1 hook and shows **Upgrade from v1** at the top of the menu.  Press OK and follow the three steps: what's there now, what changes, and a check that it all worked.  The adapter stays `eth0` the whole time, nothing switches until the next boot, and from then on updates come through the Homebrew Channel.

**Over SSH:** run `sh LG-USB-2-ETH0.sh install`.  It replaces the v1 hook in place (same file name).

Either way, if you had "disabled" v1, `status` and the app flag it: on TVs where `run-parts` is busybox's, the `.disabled` file kept running at boot.  `disable` moves it out of `init.d`, or `install` replaces it.  See the [changelog](CHANGELOG.md) for everything that changed.

<details>
<summary><b>The three steps in the app</b></summary>

<br>

**Step 1: what's there now.**  Where the v1 hook is and what it does at every boot, whether your adapter is `eth0` right now, and that the upgrade doesn't touch the network.

<img src="assets/screenshots/app-upgrade-1.png" width="100%" alt="Upgrade from v1, step 1 of 3, what's there now: the v1 boot hook is installed and renames eth0 at every boot, the USB adapter is eth0 right now, and the upgrade doesn't touch the network" />

**Step 2: what changes.**  The v1 hook is replaced in place by this version's, which follows the app's updates.  Nothing switches now, the new hook only acts when an adapter is plugged in, and Turn everything off undoes it all.

<img src="assets/screenshots/app-upgrade-2.png" width="100%" alt="Upgrade from v1, step 2 of 3, what changes: the v1 hook is replaced in place by a link to the script inside the app, nothing switches now, and the new hook only acts when an adapter is plugged in" />

**Step 3: upgraded and checked.**  The app upgrades, then checks the new hook is in place, the old v1 file is gone, and the adapter is still `eth0`.  If anything didn't work, it shows what went wrong and points you to Report for GitHub.

<img src="assets/screenshots/app-upgrade-3.png" width="100%" alt="Upgrade from v1, step 3 of 3, done: the boot hook is this version's, the old v1 file is gone, the USB adapter is still eth0, and Run at every boot is on" />

</details>

## Development and tests

The test suite runs the script against a fake `/sys` and a fake `ip`, so it needs no TV and no root, and touches nothing on your machine:

```sh
tests/run.sh busybox   # busybox sh with only busybox applets on PATH, closest to the TV
tests/run.sh dash
tests/run.sh bash
tests/run.sh busybox watch   # only tests whose name contains "watch"
```

CI runs ShellCheck and the whole suite under all three shells on every push, builds the TV app, and checks the issue forms.

<details>
<summary><b>What the tests cover, and the other tools in this repo</b></summary>

<br>

The tests cover swapping and reverting, Wi-Fi and tethering being left alone, MAC pinning, rename retries and rollback, the SSH session warning, the boot hook with and without an adapter, a late adapter, `--watch` hotplug, disable and enable, upgrading from v1, `--module` checks, moving an adapter to a new driver and falling back when that fails, `get-driver` refusing unknown kernels and bad checksums, falling back to the mirror and picking the driver by chip and adapter, `test-driver` (a driver that works, one that doesn't load, and one that froze the TV), keeping the faster driver after standby, the Wi-Fi fallback (and leaving Wi-Fi alone when it's already on), blocking updates with and without the Homebrew Channel's block (and undoing only its own changes), flagging a 100 Mbit/s or half-duplex link, the speed test, updates (refusing a bad checksum, for the app and the plain script, and what's new after one), and the report.  A fake `curl`, `luna-send`, `nyx-cmd`, `insmod` and `iptables` stand in for the network and the TV's services.

- **The TV app** is in `webos-app/`.  `webos-app/build.sh` builds the IPK and its Homebrew Channel manifest (it needs `ares-package` from `@webos-tools/cli`).
- **Screenshots** come from the built app running in a desktop browser with made-up data.  After changing the app, `sh webos-app/build.sh && node scripts/screenshots/take.js` takes them again (it needs Playwright and ffmpeg).
- **The recording** at the top of the TV app section is from a real TV: open the app on the TV, forward its web inspector over SSH (`ssh -N -L 19998:127.0.0.1:9998 root@TV`), and run `node scripts/screenshots/record-tv.js`.  It only opens the Wi-Fi backup and report boxes, closes them with BACK, and changes nothing.
- **The banner** is `scripts/banner/banner.html`, made from the app icon and the status screenshot: `node scripts/banner/make.js` renders it to `assets/banner.webp`.
- **The firmware audit:** `scripts/firmware-audit/audit.sh` unpacks an LG firmware file and lists the USB network drivers its kernel has ([docs/firmware-audit.md](docs/firmware-audit.md)).
- **Driver builds:** `scripts/driver-build/build.sh` builds a driver for one kernel from LG's source and checks it ([docs/driver-build.md](docs/driver-build.md)).

Releases are made by pushing a `v*` tag.  The release workflow runs the tests, checks the tag against `VERSION` in the script, builds the app, and publishes the script, `SHA256SUMS`, the IPK, its manifest and the AI knowledge base (`lg-usb-2-eth0-for-ai.md`).  Then it tells ohmybahgosh.dev to refresh its Homebrew Channel repository.

</details>

## Contributing

Real TV reports help most: your model, webOS version, adapter chip, and the output of `report`.  Use the [compatibility report form](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=compatibility-report.yml), or test a [new driver](#more-drivers-on-the-way) if your TV has one.  Questions and ideas go to [Discussions](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions), and a working setup is welcome in Show and tell.

Pull requests are welcome.  Please keep the script POSIX `sh` (it has to run under busybox), and add or update a test in `tests/run.sh` for any change in behavior.  For security issues, see [SECURITY.md](SECURITY.md).  Everyone here is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

<details>
<summary><b>AI-assisted pull requests</b></summary>

<br>

They're welcome too, held to the same standard as the rest of this project: say in the pull request that AI was used, make sure you understand and have reviewed every change, and test it on a real TV (say which model and webOS version).  Set your assistant up first: give it the [AI knowledge base](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/lg-usb-2-eth0-for-ai.md) (or run `sh scripts/ai-context.sh`).  Coding agents read [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md) on their own.  See [CONTRIBUTING.md](CONTRIBUTING.md) for the details.

</details>

## Thanks

A big thank you to **[DonZoomik](https://github.com/DonZoomik)** for [webos-r8152](https://github.com/DonZoomik/webos-r8152).  He found the right kernel source in LG's open-source bundles, built Realtek's current driver for webOS 25 under its own name so it can sit beside the TV's built-in one, and tracked down the scatter-gather setting that hangs the TV's USB controller.  He also published careful benchmarks.  That work is what turns a USB adapter on these TVs from "works, but drops out" into a steady connection, and `get-driver`, `--module` and the drivers built here all rest on it.  If it helps you too, go give his repo a star.

Thanks to **[mbenitez343](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix)** too, for building and sharing the `r8152` driver that brings wired USB Ethernet back to 2024 LG TVs, to **[OCT0PUSCRIME](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver)** for building ASIX's driver for webOS 5, testing it with LG-USB-2-ETH0 and sharing his build steps, to **[dd3git](https://github.com/dd3git/lg-webos-ax88179-driver)** for the ASIX driver for 2025 TVs, source included, and to **[throwaway96](https://github.com/throwaway96/webos-kernel-drivers)** for building kernel modules for so many webOS chips.

Thanks also to the [webOS Homebrew](https://www.webosbrew.org/) project for the Homebrew Channel and the startup hooks this script relies on, and to [RootMyTV](https://rootmy.tv/) for making rooting possible.

## License

MIT.  See [LICENSE](LICENSE).  Made by **OhMyBahGosh** ([@ohmybahgosh](https://github.com/ohmybahgosh)).  Not affiliated with LG Electronics.
