# Changelog

All notable changes to LG-USB-2-ETH0.  Versions follow [semantic versioning](https://semver.org/).

## [2.4.7] - 2026-11-05

### Added

- **A firmware audit.**  `scripts/firmware-audit/audit.sh` unpacks an LG firmware file and lists the USB network drivers its kernel has.  [docs/firmware-audit.md](docs/firmware-audit.md) has the results for 13 models from 2019 to 2025, webOS 26 included.  Among other things, it shows the C2, C3, C4 and UR9000 share one kernel, and that the 2024 B4 and QNED85 share the 2025 B5's, so dd3git's ASIX driver fits them too.
- **`report` names the chip and the built-in USB network drivers**, from `/lib/modules/<kernel>/modules.builtin`.  Compatibility reports now show which drivers a TV has without anyone needing to look.

### Changed

- **A warning in the README to keep firmware updates off on rooted TVs.**  LG's current firmware, webOS 26 included (43.21.94 for the C2, 43.21.96 for the C3, C4 and C5), patches the known root methods.  It explains how to turn updates off and block them, and where to watch for new root methods.

## [2.4.6] - 2026-11-04

### Added

- **Two more sources of faster drivers.**  `get-driver` and the app now offer [dd3git's](https://github.com/dd3git/lg-webos-ax88179-driver) ASIX AX88179 driver for kernel `5.4.268-294.24.papikonda.2` (2025 B5 on webOS 25, where an AX88179A wasn't detected), and [throwaway96's](https://github.com/throwaway96/webos-kernel-drivers) `r8152` and `ax88179_178a` for TVs with the Realtek K5Lp chip on kernel 4.4.84.  Both are mirrored in lg-webos-usb-drivers too.

### Changed

- **Drivers can be built per chip.**  throwaway96's modules are built for a chip rather than one exact kernel, so `get-driver` also checks the chip name.  When a TV has more than one known driver, it offers the one for the adapter plugged in.
- **A new README banner and speeds chart.**  The banner now says Realtek and ASIX drivers, and comes from `scripts/banner/banner.html` (`node scripts/banner/make.js`), so it can be redone when the app changes.  The speeds chart adds the two ASIX results.
- **A known driver may name only the base kernel version.**  Some builds say `5.4.268` inside rather than the TV's full kernel name, and the TV loads them.  The script now accepts that only for a file whose SHA-256 is pinned for the exact kernel running, and keeps the strict check for every other `--module`.

## [2.4.5] - 2026-11-04

### Added

- **A faster driver for ASIX adapters on webOS 5.**  `get-driver` (and the app's Faster driver switch) now offers [OCT0PUSCRIME's](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver) build of ASIX's AX88179/178A driver for kernel `4.4.84-612.jcl4tv.40` (2020 UN7300), whose kernel has no ASIX driver.  Like the others, it's pinned to a fixed commit and kept only if its SHA-256 matches, and only offered when an adapter it supports is plugged in.  Tested on a 55UN7300PUF with a TP-Link UE306 ([discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3)).

### Changed

- **The drivers don't depend on their authors' repositories anymore.**  All three modules `get-driver` offers are now also mirrored, byte for byte and credited to their authors, in [lg-webos-usb-drivers](https://github.com/ohmybahgosh/lg-webos-usb-drivers).  `get-driver` still downloads from the author first, and uses the mirror only if that fails.  The pinned SHA-256 decides either way.
- "Faster Realtek driver" is now just "Faster driver", in the app and the menu, since it's not only for Realtek adapters anymore.  The app's confirm screen names whoever built the driver for that TV.

## [2.4.4] - 2026-11-04

### Changed

- **What's new shows after an update, once the app opens again.**  Before, the update screen showed the release link just before the app closed.  Now it says it's installing, and the new version opens with a short list of what changed in it.  It shows once, after an update in the app or through the Homebrew Channel.

## [2.4.3] - 2026-11-04

### Fixed

- **The report's "Drivers loaded" line missed drivers built into the kernel.**  It only looked in `/sys/module`, and a built-in driver can have no folder there, like `ax88179_178a` on a 2024 G4.  It now also lists the driver each USB adapter is using.
- **The TV app's compatibility report left out the Wi-Fi backup.**  The "Options used" field now includes `--wifi-fallback` when it's on.

### Changed

- The README shows all three steps of the Upgrade from v1 walk-through.
- The first ASIX report: an AX88179 adapter works out of the box on a 2024 G4 with webOS 25 ([#2](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/2)).  It's in the Tested adapters and webOS compatibility tables.

## [2.4.2] - 2026-11-04

### Fixed

- **No connection after waking from standby**, with the faster driver (`--module`).  Standby resets the TV's USB ports and the adapter comes back on `cdc_ncm`.  The boot hook moved it back to the faster driver within seconds, while webOS was still reconnecting, and on a C2 webOS then showed no connection until a reboot.  Now the hook waits for webOS to reconnect first (up to 30 seconds), moves the adapter, and checks that webOS reconnects it.  If not, it takes the link down and up, and if that doesn't help either, it gives the adapter back to `cdc_ncm` until the next boot.  Each step is logged.

## [2.4.1] - 2026-11-04

### Added

- **Upgrade from v1, step by step, in the TV app.**  When the app finds a v1 boot hook (running, or "disabled" inside `init.d`), an Upgrade from v1 row shows at the top.  It walks through what's there now, what changes, then upgrades and checks the result: the new hook is in place, the old file is gone, and the adapter is still `eth0`.  No SSH needed, and nothing switches until the next boot.  The status line no longer tells app users to "Run 'install'".

### Changed

- The repository is ready for others: questions and ideas go to Discussions (Q&A, Ideas and Show and tell, with forms), blank issues are off, and there's a `SUPPORT.md` and a code of conduct.  A new README banner matches the one on ohmybahgosh.dev, and the TV app animation is now recorded on a real TV (`scripts/screenshots/record-tv.js`).  `SECURITY.md` lists everything the script does as root again, including updates, the speed test and the Wi-Fi backup.

## [2.4.0] - 2026-11-02

### Added

- **Wi-Fi as a backup** (`--wifi-fallback`, and a switch in the TV app).  If `eth0` loses its cable link for a minute while Wi-Fi is off, the boot hook turns Wi-Fi on, so the TV joins a network it already knows.  Once the cable has worked for 30 seconds, it turns Wi-Fi off again, so traffic goes back to the adapter.  It only turns Wi-Fi off if it turned it on, even across a reboot, and does nothing when Wi-Fi is already on.  Off by default.
- `status`, the app and the report flag an adapter whose cable link is only 100 Mbit/s (or 10), or half duplex.  That's usually a cable with only two wire pairs, and it makes the adapter no faster than the built-in port.

### Changed

- The README shows the TV app: screenshots of the status screen, speed test, GitHub report and updates, a short GIF, a before-and-after picture, and a chart of measured speeds.  `scripts/screenshots/take.js` takes the app screenshots again from the built app with made-up data.

## [2.3.2] - 2026-11-02

### Added

- **A knowledge base for AI assistants,** so contributors can set up Claude, ChatGPT, Copilot or a coding agent properly: `AGENTS.md` and `CLAUDE.md` (read by coding agents on their own), `docs/ai/GUIDE.md` (the rules, where each kind of change goes, how to test), and `scripts/ai-context.sh`, which builds `lg-usb-2-eth0-for-ai.md` with all of it plus every function in the script.  Each release attaches a copy.
- `CONTRIBUTING.md`, and an AI-use section in the pull request template.

## [2.3.1] - 2026-11-02

### Added

- `get-driver` knows a second driver: [mbenitez343](https://github.com/mbenitez343/lg-webos-2024-ethernet-fix)'s `r8152` for 2024 QNED and OLED (K25lp / Paparoa) on webOS 25, kernel `5.4.268-294.17.paparoa.pine.2`, where LG removed the Realtek driver.  Gigabit RTL8152/RTL8153 adapters only.  Pinned to a fixed commit and checked against its SHA-256, like the first one.
- The adapter can be moved to the new driver from `cdc_ether` too, not only `cdc_ncm`.  That's what a Realtek adapter lands on when the kernel has no Realtek driver.

### Changed

- A driver is only offered (in `get-driver`, `status`, the menu and the app) when a plugged-in adapter is one it supports, checked by USB ID.  An adapter with no driver at all counts too.
- The driver takeover only moves adapters the module lists as supported, so other USB network devices, like a phone tethered over `cdc_ether`, are never touched.

## [2.3.0] - 2026-11-02

### Added

- **The TV app** (`org.ohmybahgosh.lgusb2eth0`): status at a glance and switches for everything, run as root through the Homebrew Channel, so no SSH is needed.  Built with `webos-app/build.sh` and published with each release, with a Homebrew Channel manifest.
- **Speed test:** `speedtest` (and in the app) measures latency, download and upload against Cloudflare's nearest server.  The last result goes into `report` and the compatibility report.
- **Updates:** `update` checks the latest release and installs it after checking its SHA-256.  In the app it updates the whole app and reopens it; on its own the script replaces itself.  If the Homebrew Channel already has this project's repo, the app leaves updates to it.
- **Report QR code** in the app: opens a compatibility report on your phone with the TV, adapter, result, options, speed and report filled in.
- `status --json`, for the app and for scripts.
- `get-driver --file PATH`, to use a driver module you downloaded on another computer (when the TV can't download it itself).  It's checked against the same SHA-256.
- `--no-watch`, `--no-module`, `--no-mac` to turn a setting off again.

### Changed

- The boot hook is now a link to the script, with its settings in `/var/lib/webosbrew/lg-usb-2-eth0.conf`.  `install` keeps every setting you don't change, and upgrades a 2.0 to 2.2 hook in place.
- The log moved to `/var/lib/webosbrew/lg-usb-2-eth0.log`, so it survives a reboot.  It starts over at 32 KB.
- Downloads use HTTPS only, with time limits, and say what to do when they fail (an old certificate store or a wrong clock, mostly).
- The faster-driver option only shows (in the app and the menu) when it fits this TV.

### Fixed

- After standby, the adapter came back on `cdc_ncm` and stayed there.  The hook now moves it back to the faster driver.
- A changed or missing module, or one built for a kernel the TV no longer runs (after a firmware update), is skipped at boot instead of loaded.  `status` says why.
- The background check costs next to nothing now: about 0.07 ms every 5 seconds on a C2.
- Wi-Fi Direct (`p2p0`) was sometimes shown as the TV's Wi-Fi.

## [2.2.0] - 2026-11-01

### Added

- Driver takeover: with `--module`, the adapter is moved from the generic `cdc_ncm` driver to the module's driver at boot, on `apply`, and on replug with `--watch`.  If the new driver doesn't take it within a few seconds, it goes back to `cdc_ncm`.  Each adapter gets one try per boot.
- `get-driver`: downloads a better driver module when one is known to work on your exact kernel.  The first one is DonZoomik's `r8152_oot` for kernel `5.4.268-329.ptl4tv.5` (webOS 25 on the 2024 C4 and 2022 C2).  The download comes from a fixed commit, and the file is kept only if its SHA-256 matches.
- `--driver NAME`, for a module whose driver name can't be read from the file.
- Scatter-gather is turned off on the new driver, which avoids a USB controller hang DonZoomik found on these TVs.
- `status` warns when traffic goes out over Wi-Fi instead of the adapter.  webOS prefers Wi-Fi while it's connected, which was spotted on a real C2.
- `status` suggests `get-driver` when one is known for your kernel, and warns when DonZoomik's `r8152-autobind` hook and `--module` are both set up.
- First real-TV report in the compatibility table: 2022 C2 on webOS 25 with an RTL8156.

### Changed

- `--module` now refuses a module built for another kernel, before loading it.
- `apply` uses the installed hook's module, so it switches drivers too.

### Fixed

- Wi-Fi modules that sit on the USB device itself showed their driver as "usb".  `status` and `report` now show the real driver.
- `report` left the carrier blank for an interface that's down.  It now says `down`.
- Combo Wi-Fi and Bluetooth chips showed the Bluetooth driver for Wi-Fi.  Bluetooth, audio and HID interfaces are now skipped.

## [2.1.0] - 2026-11-01

### Added

- `--watch`: the boot hook keeps following the adapter after boot.  Plug it in and it becomes `eth0`.  Unplug it and `eth0` goes back to the built-in port, so the TV is never left without an `eth0`.
- `report`: a short, paste-ready block for GitHub issues, with MAC addresses masked.  Also in the menu.
- `status` shows whether `--watch` is on and whether the hook's background job is running.
- More known USB Ethernet chip IDs (Apple, Samsung, NVIDIA, Lenovo and more ASIX), so `status` spots more adapters that have no driver.
- A test suite (`tests/run.sh`) that runs the script against a fake `/sys` and a fake `ip` under busybox `sh`, dash and bash.
- CI: ShellCheck and the test suite on every push and pull request.
- Releases with a `SHA256SUMS` file, published from tags.
- Issue templates for compatibility reports and bugs, and a security policy.

### Changed

- Renames are retried up to 3 times.  webOS can bring an interface back up between `down` and the rename, which made it fail with "Device or resource busy".
- `install`, `uninstall` and `disable` stop the hook's background job first.
- `apply` and `revert` say when the switch is still running after 20 seconds, instead of printing a partial log.
- Wi-Fi shows as "connected" in `status` rather than "cable in".
- No colors when the output isn't a terminal, or when `NO_COLOR` is set, so logs and pasted output stay clean.
- The hook appends the system directories to `PATH` instead of putting them first.
- README rewritten: safety and undo up front, table of contents, adapter guide, sourced speed table, FAQ, development guide.

### Security

- `--module` only accepts plain path characters (letters, digits, `.`, `_`, `-` and `/`).  The path is written into a root boot script, so a crafted path could otherwise have run commands at every boot.

## [2.0] - 2026-10-26

### Changed

- The built-in port is only renamed when an adapter is actually there.  v1 renamed `eth0` to `eth2` at every boot even with no adapter plugged in, which left the TV with no `eth0`.
- The boot hook waits for the adapter in the background (120 s by default) and never holds up the Homebrew Channel startup.
- The adapter is found automatically and checked to really be USB Ethernet, so `eth1`, `eth2` and `usb0` all work and the Wi-Fi module is never grabbed.
- A failed rename puts the old names back.
- `apply` and `revert` run detached, so they finish when the SSH session drops, and warn first if you're connected through a port that's about to change.
- A disabled hook is moved out of `init.d`.  v1 renamed it to `S01fix-eth.disabled` inside `init.d`, where busybox `run-parts` still ran it.

### Added

- `status` / `doctor`.
- `--mac`, `--wait`, `--module` and `-y`.

## [1.0]

- First release: renames `eth0` to `eth2` and `eth1` to `eth0` at every boot.

[2.2.0]: https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/tag/v2.2.0
[2.1.0]: https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/tag/v2.1.0
