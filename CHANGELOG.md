# Changelog

All notable changes to LG-USB-2-ETH0.  Versions follow [semantic versioning](https://semver.org/).

## [2.6.1] - 2026-11-06

### Fixed

- **Test a new driver shows up on TVs that don't report their chip through `nyx-cmd`.**  A 2020 UN7300 on webOS 5 ([#6](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/6)) answered nothing there, so drivers built for its chip (K6Lp) weren't offered and the row disappeared once the app loaded.  The script now falls back to the chip name LG's firmware keeps in `/etc/prefs/properties/machineName`, which is built per chip.  The report's `Chip:` line uses it too.

## [2.6.0] - 2026-11-06

### Added

- **Drivers that need `usbnet` work on kernels that leave it out.**  LG's LM21A-family LCD kernels have no `usbnet`, the core ASIX AX88179, Davicom, Aquantia and most other USB Ethernet drivers build on.  For those kernels the mirror now has the kernel's own `usbnet.ko`, pinned by SHA-256 like any driver.  `get-driver`, **Test a new driver** and boot-time loading download it alongside the driver, check it, and load it first.  Kernels that have `usbnet` built in are untouched.
- **ASIX, Davicom and Aquantia drivers to test for the 2022 UQ LCDs (LM21AN chip)**, on both of its kernels, built on that `usbnet`.
- **Drivers to test for the 2023 UR LCDs (LM21ANN chip) on webOS 23, 24 and 25:** Realtek (`r8152_oot` and the kernel's own `r8152`), ASIX AX88179, Davicom DM9601 and Aquantia AQC111, with `usbnet`, for `5.4.96-955.20.namtok.1`, `5.4.268-966.8.4.okapi.pine.1` and `5.4.268-966.15.ptl4tv.8`.  Built from LG's published source with each TV's own config.
- **Drivers to test for the 2021 UP and NANO LCDs (LM21A and LM21U chips) on webOS 6:** Realtek, ASIX AX88179 and Davicom DM9601, with `usbnet`, for `4.4.84-899.19.koli.1` and `4.4.84-899.kcl4tv.19`.  LG's published source is older than these kernels and turns off one option (`CPU_SW_DOMAIN_PAN`) the TVs have on, so that was put back to match; the TVs' own kernels confirm it.
- **294 drivers are now waiting for testers.**
- **The README's webOS 26 section is a table by model:** which webOS 26 firmware can still be rooted, which drivers are built in, and whether added drivers can load.
- **More of the firmware audit on webOS 26:** the 2024 B4 and 2025 B5 (43.22.72) and the 2024 K8LpN2 LCDs (43.22.13) have only `asix`, with module signing off.  The C6 and G6 moved to `6.12.44-352` in 43.21.69 and still only load drivers LG signed, while the 2022 to 2025 OLEDs' `6.12.44-352` doesn't, so the script checks the running kernel rather than its name.  The 2021 UP and NANO LCDs (LM21A, LM21U) on 4.4 kernels have no USB network drivers either.
- **A tested adapter from Reddit:** the TP-Link UE306 on a 2024 C4, about 300 Mbit/s.

### Fixed

- **The README's driver list puts the LM21A-family kernels under the right webOS version and chip.**
- **The firmware audit's 27ART10AKPL is the StanbyME (the 2022 rolling-stand screen), not the StanbyME Go.**
- **The driver build adds the exports of our own modules** (like `usbnet.ko`) when it checks a driver built on them.

## [2.5.0] - 2026-11-06

### Added

- **After a firmware update, Faster driver switches to the new kernel's driver in one press.**  A firmware update can change the kernel while root survives.  The driver set up before is then built for the old kernel, so it's skipped at boot and the adapter falls back to the TV's own driver.  The script now remembers the kernel it was set up on, and when a driver is known for the new kernel and the adapter, the app's **Faster driver** row says so and one press downloads it and moves the adapter over.  When none is known yet, `status` points to **Test a new driver** if there's one to test, or asks for a report.  The report says which kernel it was set up on.
- **Drivers to test for three more kinds of adapter: Aquantia AQC111U and AQC112 (5G and 2.5G), Davicom DM9601 and Microchip LAN7800/LAN7850.**  None of LG's kernels include these drivers, not even on its own OLED chips, so these adapters get no driver on any LG TV.  159 new modules: for the 54 kernel and chip combinations already built for (`aqc111` only on 5.4 kernels), and for `5.4.268-329.ptl4tv.5`, the C2, C3, C4 and G4's kernel.  Built from the same LG source and config with the same checks.  **Test a new driver** offers one when its adapter is plugged in, and no longer when the adapter plugged in already has a driver and none of the new ones is for it.  265 drivers are now waiting for testers, with the LM21AN ones below.
- **A virtual TV scenario for a firmware update** (`c2-fwupdate`): a C2 set up with a driver whose kernel then changed.
- **Realtek drivers to test for the 2022 UQ LCDs (LM21AN chip).**  The firmware audit found LG's LM21A-family kernels have no USB network drivers at all, not even `usbnet`.  Realtek's driver doesn't need it, so `r8152_oot` (RTL8152, RTL8153, RTL8156) and the kernel's own `r8152` are built from LG's LM21AN source for both of its kernels.  ASIX and the generic drivers need `usbnet` loaded first, which comes later.
- **webOS 26:** the script knows when the kernel only loads modules LG signed (the 2026 models' webOS 26 kernels enforce it; the 2022 to 2025 OLEDs' webOS 26 kernel doesn't).  It doesn't offer, test or load drivers there, and `status`, the report and `install --module` say why.  The JSON has `sigEnforced`.  It reads built-in drivers from `/usr/lib/modules`, where webOS 26 keeps them.
- **The firmware audit covers webOS 26 and LG's LM21A LCDs.**  2026 OLEDs on LG's own chip have every driver built in.  The 2026 B6 lacks `ax88179_178a`, and the 2026 QNED7S has only `asix`.

### Fixed

- **The in-app update is ready for webOS 26.**  Its installer can't read an IPK from `/tmp` (people hit this installing the Homebrew Channel there), so the download goes to `/media/developer/temp` when the TV has it.  The README's manual install uses that folder too.  Not tried on a webOS 26 TV yet.
- **The README no longer says all of webOS 26 is patched.**  Only firmware released after October 10, 2026 is, per the EPK archive's rooting guide.
- **The driver build handles LG's MediaTek (LM21A) and webOS 26 trees:** their relative include folders, a release set through `EXTRAVERSION`, and (with `SUBLEVEL_FROM_KERNEL=1`) a Makefile that says 6.12.0 for a 6.12.44 kernel.
- **The driver build copies a driver's own header** (like `lan78xx.h` and `aqc111.h`), so drivers that have one build.

## [2.4.16] - 2026-11-06

### Fixed

- **A driver test works when Realtek mode already moved the adapter to the kernel's own `r8152`.**  The first driver test report ([#5](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/5), a 2024 G4 on `5.4.268-320`) came back "not used": the adapter was on the TV's built-in `r8152`, working, and the test only moved adapters off the generic drivers.  Now a driver whose module lists the adapter takes it from the built-in `r8152` too, for a test and for **Faster driver**.  The test report also says which driver the adapter was on before.

## [2.4.15] - 2026-11-06

### Added

- **A virtual TV for development** (`scripts/virtual-tv/`): the TV app on your computer, with its commands running the real script on a made-up TV (a C2 or a C9), and headless recordings with the remote's keys.  No TV needed to try the app or record it.
- **Clips of the TV app in the README**: Faster driver, Test a new driver, Realtek mode and Switch now, and new screenshots, all from the virtual TV (`scripts/virtual-tv/make-media.sh`).

### Fixed

- **The app only shows Realtek mode for adapters it can help** (Realtek RTL8152 and RTL8153), not for every adapter on a kernel with `r8152`.
- **A driver test report says "link unknown"** instead of "link M" when the adapter hadn't reported its speed yet.

## [2.4.14] - 2026-11-06

### Added

- **Realtek mode: the TV's own Realtek driver, with nothing to download.**  Many LG kernels build `r8152` in, from 2019's C9 to webOS 25, but none of them can switch a Realtek adapter to its Realtek USB mode, so the adapter stays in its standard mode on the generic `cdc_ncm` or `cdc_ether` driver.  Now an RTL8152 or RTL8153 adapter left there is switched over so `r8152` takes it, at boot, with `apply`, and with `--watch` when it's plugged in.  Once per plug-in, and if `r8152` doesn't take it within 5 seconds, it goes back to the mode it was in and `status` suggests a driver from `get-driver` or `test-driver` instead.  On by default, except with `--module`.  Turn it off with **Realtek mode** in the app or `--no-realtek-mode`.  It's new and hasn't been reported on a TV yet.
- **`status` explains** when a Realtek adapter is in its standard mode on a kernel that has `r8152`, and the report shows how Realtek mode went.
- **A FAQ on built-in drivers**, listing the kernels in the firmware audit with `r8152` built in.

## [2.4.13] - 2026-11-06

### Fixed

- **Status now lists drivers built into the kernel.**  "USB network drivers on this kernel" only counted drivers with a `/sys/module` folder or a `.ko` file, so a built-in `r8152` (like on a 2019 C9) was missing and looked absent, the same way it never shows in `lsmod`.  Built-in drivers now show as `(built in)`, from `modules.builtin` or the kernel's registered USB drivers, and the report's "Drivers loaded" line counts them too.  Thanks to RenderedKnave on r/webos for pointing it out.

## [2.4.12] - 2026-11-05

### Added

- **RTL8156 (2.5 gigabit) drivers to test for 2020 TVs on kernel 4.4.**  Realtek's r8152 v2.22.1, ported back to 4.4 (`scripts/driver-build/r8152-4.4.patch`), as `r8152_oot` for `4.4.84-612.40.jimna.1` and `4.4.84-612.21.6.jardine.2` on K6Lp and K6Hp, and for `4.4.84-611.japoon.14` on K6Lp.  The kernel's own `r8152` still wins for RTL8152 and RTL8153 adapters.
- **Drivers to test for `4.4.84-612.jcl4tv.40` on K6Lp** (the kernel in OCT0PUSCRIME's webOS 5 build): `r8152` and `r8152_oot`.
- **Drivers people report working move to `get-driver` on their own.**  When a driver test report says it works, a GitHub Action moves that driver from the list to test to a new list of tested drivers (`TESTED_DRIVERS`), runs the checks and opens a pull request for review.
- **A check that the driver lists agree.**  `scripts/drivers.py check` (run in CI) makes sure the script's tables, the mirror's `SHA256SUMS`, the README's driver list and its badge all match.  `scripts/drivers.py update` rewrites the README list and badge from the script.

### Changed

- The app and `test-driver` name RTL8156 among the adapters a driver may be for.

## [2.4.11] - 2026-11-05

### Added

- **Drivers to test for the webOS 25 paparoa kernels.**  `r8152_oot` and `ax88179_178a` for `5.4.268-294.17.paparoa.pine.2` on K24, K8Hp, K8Hpp, K8LpN and K8LpN2, and for `5.4.268-294.15.paparoa.3` and `.4` on K24N and K25Lp.  Where mbenitez343's tested `r8152` already covers the adapter, that one still wins: these add RTL8156 and ASIX.

## [2.4.10] - 2026-11-05

### Added

- **More drivers to test, for Realtek-chip TVs on webOS 22 and 25.**  `r8152_oot` for `5.4.268-294.24.papikonda.2` on K24N, K25Lp, K8Hp, K8Hpp, K8LpN and K8LpN2, and for `5.4.268-294.ptl4tv.24` on K24N and K25Lp (with `ax88179_178a` there).  For webOS 22 TVs with K8 chips (like the 2022 NANO75), which have no Realtek or AX88179 driver at all, `r8152_oot` and `ax88179_178a` for `5.4.96-115.30.mole.2` and `5.4.96-115.28.mirima.1` on K8Hp, K8Lp and K8Ap, from LG's real K8 source.  Each is built with its TV's own config.  The script's list of drivers to test is now one table.
- **Drivers to test for Realtek-chip TVs on webOS 23 and 24, and more on webOS 22.**  `r8152_oot` and `ax88179_178a` for the webOS 24 kernels (`5.4.268-223.*` on K24, K24T, K8Hp, K8Hpp, K8HpT, K8LpN and K8LpN2, which includes 2022 OLEDs updated to webOS 24, and the first webOS 24 firmware's `5.4.96-223.*`), the webOS 23 `5.4.96-132.*` kernels (K8Hp, K8Hpp, K8LpN) and five older webOS 22 `5.4.96-115.*` kernels.  The `5.4.268-223` ones come from the nearest 5.4.268 source, since LG hasn't published theirs.
- **Drivers to test for 2020 TVs with the K6Hp chip** (like the NANO87): `r8152` and `ax88179_178a` for `4.4.84-612.40.jimna.1` and `4.4.84-612.21.6.jardine.2`, whose K6Hp config is the same as K6Lp's.  Also for `4.4.84-611.japoon.14` (the HU810P projector).
- **The driver build lists config options the source adds or changes that kernel headers use**, so a build from a neighboring kernel's source says what differs.  It also shows the end of the log when a step fails.
- **The driver build stops when the source is missing options that change kernel headers**, and `scripts/driver-build/kconfig-stub.py` writes their Kconfig from the TV's config, so a module never gets a different struct layout than the TV's kernel.

## [2.4.9] - 2026-11-05

### Added

- **Drivers to test for 2020 TVs with the K6Lp chip** (like the UN7300), which have no Realtek driver, no `cdc_ncm` and no AX88179 driver: the kernel's own `r8152` (RTL8152, RTL8153) and `ax88179_178a`, for kernels `4.4.84-612.40.jimna.1` and `4.4.84-612.21.6.jardine.2`.  `test-driver` and Test a new driver pick the one for the adapter plugged in.
- **The app says when there's a driver to test**, once, the first time it opens on a TV whose kernel has one, and offers to start the test.  It stays in the menu as Test a new driver.  Built with each TV's own config, which the firmware audit now reads from the U-Boot and zImage kernel these TVs use.
- **32-bit driver builds.**  `scripts/driver-build/build.sh` now builds for the 32-bit (ARMv7) 4.4 kernels of 2020 and 2021 TVs too, and can build a driver from LG's own kernel tree (`intree:ax88179_178a`, `intree:r8152`) for kernels that leave it out.  Checked against OCT0PUSCRIME's webOS 5 ASIX driver: LG's source, built his way, exports every symbol his module uses, and the drivers built from it match its `vermagic`.  Thanks to OCT0PUSCRIME for sharing his build steps.

## [2.4.8] - 2026-11-05

### Added

- **`test-driver`, and Test a new driver in the app, for testers.**  On a TV whose kernel has an experimental driver, one command (or one press in the app) does the whole test: downloads the driver and checks its SHA-256 and vermagic, loads it until the next restart only, moves a Realtek adapter to it, checks it gets online, and shows a report with no MAC or IP addresses.  The app shows it as a QR code that opens a filled-in driver test report, a new issue form.  A test that freezes the TV is marked before the driver loads, so it's reported as such after the restart.  `report` and `status --json` include the last test's result.
- **Building drivers from LG's kernel source.**  `scripts/driver-build/build.sh` builds a driver for one kernel, DonZoomik's way, and keeps it only if its vermagic matches, the kernel exports every symbol it uses, and (on o22 5.4.268 kernels) the USB struct offsets match.  Rebuilt from LG's C2 source, DonZoomik's driver comes out the same as his.  Realtek drivers are built for `5.4.268-329.ptl4tv.2`, `5.4.268-320`, `5.4.96-307` and K24's `5.4.268-294.24.papikonda.2`, and wait for testers before `get-driver` offers them: see [docs/driver-build.md](docs/driver-build.md).
- **The firmware audit reads newer firmware too**, whose kernel is inside the rootfs as `boot/Image.lz4` (LG's LZ4P format), and with `SAVE=DIR` keeps each kernel's image and config.

## [2.4.7] - 2026-11-05

### Added

- **A firmware audit.**  `scripts/firmware-audit/audit.sh` unpacks an LG firmware file and lists the USB network drivers its kernel has.  [docs/firmware-audit.md](docs/firmware-audit.md) has the results for 13 models from 2019 to 2025, webOS 26 included.  Among other things, it shows the C2, C3, C4 and UR9000 share one kernel, and that the 2024 B4 and QNED85 share the 2025 B5's, so dd3git's ASIX driver fits them too.
- **Block updates harder (`--block-updates`), in the app and the script.**  On top of the Homebrew Channel's Block system updates, never instead of it: it turns off webOS's own update check (`softwareUpdateEnable`), adds the update servers that block misses (`nsu.lge.com`, `snu-dev.lge.com`, `ngfts.lge.com`) to `/etc/hosts`, drops traffic to `156.147.69.32` with one firewall rule, and deletes cached update details.  With the Homebrew Channel's block off, it blocks that block's four servers too.  Right away and at every boot.  Turning it off undoes all of it.  From the findings in Homebrew Channel issue #96 and PR #264.  `status` notes when firmware updates aren't blocked at all.
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
