# Changelog

All notable changes to LG-USB-2-ETH0.  Versions follow [semantic versioning](https://semver.org/).

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
