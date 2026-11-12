# Changelog

All notable changes to LG-USB-2-ETH0.  Versions follow [semantic versioning](https://semver.org/).

## [2.11.17] - 2026-11-12

### Security

From a security review of the script and the TV app:

- **Downloads and running state live in a folder only root can write.**  They were in `/tmp` itself, and an update's IPK on webOS 26 in `/media/developer/temp`, which every app on the TV can write to (that one without the sticky bit, so any app could swap a file in it).  A driver module, `usbnet.ko`, an update or the update's IPK was checked and then used a moment later, and another app could have swapped it in between to run its own code as root.  They now go in `/tmp/lg-usb-2-eth0` and `/media/developer/temp/lg-usb-2-eth0`, folders only root can write.  Anything already at those paths (a link, or a folder another app made or can write to) is moved aside first.
- **The update's manifest is checked more strictly.**  Its version had to start with digits, and went into the install job's shell, so a tampered manifest could have run commands.  It now has to be only digits and dots, and the IPK link has to be this release's own file on GitHub.
- **Updating needs curl.**  busybox wget may not check certificates, and the update's checksum comes from the same place as the update, so an update over wget could be swapped on the way.  Driver downloads still work with wget: their checksums are built into the script.
- **Speed test numbers are checked before they go into the app's status.**

## [2.11.16] - 2026-11-12

### Fixed

- **Saved settings can't be wiped by two runs at once anymore.**  The app runs the script for its status every 30 seconds and for each action, and any run from the app can save the app's language.  Two runs saving at the same time went through the same temporary file, and on an LG G6 the settings ended up as only the language line, so the watch and Wi-Fi wake stopped (issue #26, thanks romansat for tracking it down and the reproducer).  Settings are now saved one run at a time, each through its own temporary file, and a language save only replaces the file when every other setting made it into the new copy.  A test runs eight language saves at once.

## [2.11.15] - 2026-11-12

### Fixed

- **Test a new driver no longer says "no internet" just because Wi-Fi is on.**  The adapter stays `eth1` during the test, so with Wi-Fi connected the TV's internet goes out Wi-Fi, and a ping out the adapter had no way to the internet.  A 2022 UQ76 with a TP-Link UE300 got a 1000 Mbit/s link and an address on the new driver, and still read "no internet" (issue #25).  When the internet ping can't go out the adapter, the test now pings the router the adapter got its address from, and counts that as working.
- **The test says when the router didn't answer.**  An adapter with only a 169.254 address (one the TV gives itself) is reported as `address 169.254-only` instead of `address yes`.

## [2.11.14] - 2026-11-12

### Fixed

- **The speed test no longer shows 0 Mbit/s when Cloudflare limits it.**  Run a few speed tests back to back and Cloudflare answers "429 Too Many Requests" for a while.  Those quick error answers were counted as tiny transfers, so a test showed 0 Mbit/s, or lower numbers when only some requests were limited.  Now only real transfers count, the app and `speedtest` say when Cloudflare limited a test, and a limited test stays out of the history.

## [2.11.13] - 2026-11-12

### Fixed

- **Wi-Fi wake no longer puts an adapter with no working address ahead of Wi-Fi.**  After a restart, a 2022 C2's adapter got no answer from the router and gave itself a 169.254 address, which goes nowhere.  webOS sent traffic over Wi-Fi instead, but the check that keeps the adapter first moved it back ahead, and the TV lost its internet.  It now only moves an adapter with a real address, and waits for one on wake too.
- **The adapter asks the router again.**  With Wi-Fi wake on, an adapter left with only a 169.254 address reconnects after a minute to ask the router for an address again, then every five minutes until it gets one.
- **Status reads the default route right.**  With only a 169.254 address the route reads "default dev eth0 scope link", and status and the app said traffic was "going out link".  Status also warns now when the adapter has no address from the router.

## [2.11.12] - 2026-11-12

### Changed

- **A new app icon that fills its tile.**  The old one had a frame inside the tile, so it looked smaller and boxed in next to other apps in the launcher.  The new one drops the frame and makes `#eth0` bigger, like SSH Doctor's icon.

## [2.11.11] - 2026-11-12

### Fixed

- **The USB 3.0 hint no longer says the TV has a USB 3.0 port.**  A TV's USB controller can do USB 3.0 while its ports are wired for USB 2.0 only, like a 2022 C2's, so it can't tell.  The hint now says the adapter can go faster *if* the TV has a blue USB 3.0 port.

## [2.11.10] - 2026-11-12

### Added

- **Status points you to a USB 3.0 port.**  When the adapter runs at USB 2.0 speed (about 300 Mbit/s at most) on a TV that has a USB 3.0 port, usually the blue one, status says so: plugged straight into it, or through a USB 3.0 cable or converter, the adapter can go faster.  In English, Russian and Spanish.

## [2.11.9] - 2026-11-12

### Fixed

- **Wi-Fi wake in standby no longer disconnects the adapter while the TV turns on.**  A 2022 C2 reports "Active Standby" with "Screen On" in progress as it wakes, and Wi-Fi wake took that for standby: it disconnected the adapter and connected it again two seconds later.  It now hands over only when the TV is going to standby.

## [2.11.8] - 2026-11-12

### Fixed

- **Wi-Fi wake in standby keeps the adapter first.**  With Wi-Fi kept connected for wake, webOS's connection manager put Wi-Fi ahead of the adapter once Wi-Fi passed its internet check, so traffic went over Wi-Fi.  On a 2022 C2 it happened after Wi-Fi got its own address.  Wi-Fi wake now checks every 10 seconds and puts the adapter back first if Wi-Fi has taken over, and logs it when it does.

## [2.11.7] - 2026-11-11

### Fixed

- **Wi-Fi wake in standby keeps Wi-Fi ready after a restart.**  On a 2022 C2, webOS turned Wi-Fi off at boot while the cable was connected, and once it was on again it didn't join Wi-Fi on its own, so nothing could wake the TV.  Wi-Fi wake now turns Wi-Fi on when webOS left it off, joins the network the TV already knows, and keeps the adapter first for traffic.  It checks at boot, when it's turned on, and after each wake.
- **Wi-Fi with the same address as the adapter is caught.**  With the same fixed IP set on Wi-Fi and on the adapter, traffic went out either one at random and apps like Aerial lost their connection.  `status` and the app now say so, with how to give Wi-Fi its own address, and Wi-Fi wake disconnects Wi-Fi in that case so the adapter keeps working.

## [2.11.6] - 2026-11-11

### Fixed

- **Wi-Fi wake in standby works on webOS 25 (a 2022 C2), and starts right away.**  Turning it on had no effect until the next restart; now it starts following standby as soon as it's on.  On a C2, `busctl` couldn't reach the system bus (it's at `/var/run/dbus/system_bus_socket` there), so the check for Turn on via Wi-Fi always said it was off; it now uses that bus, or webOS's own setting (`wolwowlOnOff`) when `busctl` can't tell.  It also hands over as soon as webOS says it's going to standby, since on the C2 the adapter and Wi-Fi were already down by the time the state said Active Standby, and it logs each power state change.
- **status names the right Wi-Fi to wake the TV by.**  It picked `p2p0` (Wi-Fi Direct) on a C2, whose MAC doesn't wake the TV, instead of `wlan0`.

## [2.11.5] - 2026-11-11

### Fixed

- **Faster driver works on TVs with an older busybox, like the 2018 B8 (webOS 4).**  The script stripped control characters from its JSON for the app with `tr -d '\000-\011...'`, and the older busybox `tr` on those TVs doesn't read a range after an escape, so it deleted every `-` instead.  Every path the app got lost its dashes, so **Faster driver** asked to install `/home/root/lgusb2eth0/drivers/ax88179_178a.ko`, which doesn't exist (issue #22).  The control characters are now listed one by one, and a test checks the script never uses a range after an escape in `tr` again.

## [2.11.4] - 2026-11-11

### Fixed

- **Test a new driver follows an adapter that reconnects during the test.**  Some adapters, like an AX88179A on a 2018 B8, disconnect and come back as a new USB device once a new driver takes them.  Nothing set up the new interface, so the test reported "no link" for a driver that works (issue #20).  The test now notices the adapter came back, sets it up again and waits for its address, and the report says `Reconnected: yes`.
- **`install --module` with a path that doesn't exist says what to do.**  If the driver is in LG-USB-2-ETH0's drivers folder under that name, it asks "Did you mean" with the right path, and if it hasn't been downloaded yet, it points at `get-driver` (or **Faster driver** in the app), which downloads it and prints the install command (issue #22).

## [2.11.3] - 2026-11-11

### Added

- **A tested ASIX AX88179 driver for 2018 OLEDs like the B8, C8 and E8, SK NanoCells and some UK LCDs (O18 and M16PP chips, webOS 4.0).**  On a B8 with kernel `4.4.84-150.glacier.2`, `ax88179_178a` took an AX88179A adapter as `eth0` at 1000 Mbit/s after loading its `usbnet.ko` first, with settings showing the wired connection and 222 Mbit/s over USB 2.0 (issues #12, #20 and #21).  **Faster driver** and `get-driver` offer it with its `usbnet.ko`, no testing needed.

## [2.11.2] - 2026-11-10

### Changed

- **Wi-Fi wake in standby logs why each try to reconnect the adapter didn't work.**  On wake, every try that fails now gets its own line: no `eth0` yet, `eth0` isn't the adapter yet, the adapter has no cable link yet, or no address after 10 seconds (with ConnMan's error if connecting failed).  The log also says if the adapter couldn't be put back ahead of Wi-Fi.  On a G6, the adapter came back on the second try with nothing saying why the first one failed (discussion #19).

## [2.11.1] - 2026-11-10

### Fixed

- **The TV app's menu no longer runs into the footer while it starts.**  Until the first status came in, the menu rows kept their full size, so the last ones ran past the bottom of the screen and the GitHub link sat on top of **Speed test**.  The rows now get their fitted size right away.

## [2.11.0] - 2026-11-10

### Added

- **Wi-Fi wake in standby (`--wifi-wake`), for Turn on via Wi-Fi.**  On some TVs, Turn on via Wi-Fi stops working in standby while the USB adapter is the main connection: on an LG G6 with webOS 26, the TV dropped off Wi-Fi.  With this on, just before standby the boot hook disconnects only the adapter's network session in webOS's connection manager (the adapter stays plugged in and stays `eth0`), so Wi-Fi stays ready for wake, and on wake it connects the adapter again and puts it back ahead of Wi-Fi, retrying while the adapter comes back.  It only does this when Wi-Fi is connected and Turn on via Wi-Fi is on, and if the TV loses power in standby, the next boot connects the adapter again.  Off by default.  The TV app has it as **Wi-Fi wake in standby**.  Thanks to romansat for tracking this down and sharing a working approach (discussion #19).

## [2.10.1] - 2026-11-10

### Added

- **A tested ASIX AX88179 driver for the 2017 C7 and UJ7 too (M16P chip, webOS 3.5).**  On a C7, `ax88179_178a` took a UGREEN AX88179B as `eth0` after loading its `usbnet.ko` first (the 2.9.8 fix), and got a link on USB 3 and a working connection (issues #16 and #18).  **Faster driver** and `get-driver` offer it with its `usbnet.ko`, no testing needed.

## [2.10.0] - 2026-11-10

### Added

- **A tested Realtek driver for 2017 OLEDs like the C7 and UJ7 LCDs (M16P chip, webOS 3.5).**  `r8152_oot` for kernel `4.4.3-119.drd4tv.6` works on a C7: a speed test ran at 500 Mbit/s, and the boot hook loads it and makes the adapter `eth0` at 1000 Mbit/s on USB 3 (issue #17, discussion #4).  **Faster driver** and `get-driver` now offer it, no testing needed.  It's the first driver for a 2017 TV built from LG's own source that's been reported working.

### Fixed

- **Promoting Realtek's driver leaves `usbnet.ko` with the drivers that need it.**  `scripts/drivers.py promote` moved a kernel's `usbnet.ko` along with any driver, though Realtek's and Microchip's don't use it.

## [2.9.9] - 2026-11-10

### Fixed

- **Test a new driver waits for slow webOS versions.**  When the adapter has no address after the wait, the test now takes its link down and up so webOS notices it, the way the boot hook already does after standby, and waits again before reporting.  On a 2017 C7 (webOS 3.5), Realtek's driver was reported as "no link" though it came up and ran a 500 Mbit/s speed test a moment later (issue #17).

## [2.9.8] - 2026-11-10

### Fixed

- **Drivers to test on older TVs now load `usbnet` first.**  On 4.x kernels without `usbnet` (the 2017 C7 and LJ, the 2018 B8, and some 2019 and 2021 models), the ASIX, Davicom and other drivers built on it come with their own `usbnet.ko`, which has to load first.  The script told those drivers apart by a `name=` line that modules for 4.x kernels don't have, so it skipped `usbnet.ko` and the driver failed with "unknown symbol in module".  It now also goes by the `usbnet_probe` they call.  Nothing froze: the driver just never loaded.  Run **Test a new driver** again (issues #16 and #12).

### Added

- **Driver builds check struct offsets against the TV's own kernel.**  A driver built against headers that don't match the TV's kernel can freeze it the moment it registers, the likely reason a C7 owner's own build from vanilla 4.4.3 froze in `register_netdev` (discussion #4).  `scripts/driver-build/abi-check.py` reads the symbol table out of the TV's kernel image and compares 17 small network and USB core functions, built from LG's source with the TV's config, with the same functions in the image, plus the size of `struct net_device`.  `build.sh` runs it whenever it has the image: the C7's drivers in 2.9.7 match, and so do the K24 kernels.  A module only passes as "checked against the image" when everything matches; differences are listed and leave it unchecked, for a person to look at.

## [2.9.7] - 2026-11-09

### Added

- **Drivers to test for the 2017 OLEDs like the C7, and the UJ7 4K LCDs (M16P chip, webOS 3.5).**  Their kernel `4.4.3-119.drd4tv.6` (firmware 06.10.65) has `r8152` built in, but it's too old for the RTL8153B (`Unknown version 0x6010`) and the RTL8156, and there's no `usbnet`.  Realtek's newer `r8152_oot`, ASIX AX88179, Davicom and Microchip drivers are ready to test, with a `usbnet.ko` the script loads first.  LG hasn't published this TV's kernel, so they're built from its sibling DKLP3 source with the TV's own config, read from its firmware (discussion #4).

## [2.9.6] - 2026-11-08

### Fixed

- **The older ASIX AX88178 (`0b95:1780`, like the Plugable USB2-E1000) is named as itself.**  Reports and the app called it an AX88179/178A, a different chip on a different driver.  It runs on the TV's built-in `asix` driver, which is what it already used (issue #13).

## [2.9.5] - 2026-11-08

### Fixed

- **Driver test reports say what happened to `usbnet`.**  On kernels without `usbnet`, the test loads a `usbnet.ko` before an ASIX or Davicom driver.  The report now has a `usbnet:` line saying whether it loaded, was already in the kernel, or failed, and its kernel log includes "Unknown symbol" lines and the ASIX, Davicom and Microchip drivers' own messages.  A report from a 2018 B8 (issue #12) couldn't show which part was missing.

## [2.9.4] - 2026-11-08

### Added

- **Drivers to test for the 2017 LJ HD and Full HD LCDs (M2R chip, webOS 3.5), like the 32LJ590U and 43LJ614V.**  Their kernel `4.4.3-78.drd4tv.2` (firmware 05.80.35 to 06.10.60) has no USB network driver at all, not even `usbnet`.  Realtek (`r8152.ko` and `r8152_oot.ko`, for RTL8152, RTL8153 and RTL8156), ASIX AX88179 and Davicom drivers are now ready to test, with a `usbnet.ko` the script loads first, built from LG's DMR kernel source.  There's no Microchip build: this kernel leaves out the PHY library it needs.

## [2.9.3] - 2026-11-08

### Added

- **Drivers to test for the 2017 UJ63, UJ67 and UJ70 (K3LP chip, webOS 3.5).**  Their kernel `4.4.3-208.drd4tv.3` (firmware 06.10.70 and 06.10.75) has `usbnet` and ASIX's AX88772 driver built in, so those adapters already work.  Realtek (`r8152.ko` and `r8152_oot.ko`, for RTL8152, RTL8153 and RTL8156), ASIX AX88179, Davicom and Microchip drivers are now ready to test, built from LG's DKLP3 kernel source with the TV's own config.

## [2.9.2] - 2026-11-08

### Added

- **Drivers for the 2019 LM63 on its older firmware.**  The LM63 and other small 2019 HD LCDs (M3R chip) on firmware 04.72.20 and 05.00.03 run kernel `4.4.84-432`, not the `4.4.84-433` that already had drivers to test.  The same set now covers them: Realtek (`r8152.ko` and `r8152_oot.ko`), ASIX AX88179 and Davicom, with a `usbnet.ko` loaded first.

## [2.9.1] - 2026-11-08

### Added

- **Drivers for 2018 OLEDs and NanoCells.**  The B8, C8, E8 and other 2018 OLEDs, the SK NanoCells and some UK LCDs (O18, M16PP and M16PP LITE chips, kernel `4.4.84-150.glacier.2`, webOS 4.0) have Realtek's `r8152` built in but nothing else.  RTL8156 (`r8152_oot.ko`), ASIX AX88179, Davicom DM9601 and Microchip LAN78xx, with a `usbnet.ko` loaded first, are waiting for testers.  One build covers all three chips: their firmware has the same kernel config, and the drivers are built with it.

## [2.9.0] - 2026-11-07

### Added

- **The TV app speaks Spanish.**  It follows the TV's menu language like Russian does, and the Language row now goes Auto, English, Русский, Español.  That covers the app's screens, the problems and tips on the status screen, and the messages the boot hook shows on the TV.  [Screenshots in Spanish](assets/screenshots/es/).
- The guide for contributors and AI assistants, `AGENTS.md`, `CONTRIBUTING.md` and the AI knowledge base (`lg-usb-2-eth0-for-ai.md`) now explain the translations: where new text goes, how to add a language, and `node tests/check-i18n.js`.

### Changed

- The translation check also catches English left over in languages that use the same alphabet, not only in Russian.

### Fixed

- The status screen no longer stops if the script's status has no tips list at all (an older script on the TV during an update).

## [2.8.1] - 2026-11-07

### Added

- **More of the app in Russian.**  The problems and tips on the status screen (the script's messages) are translated now, and where they say to run a command, the Russian points at the app's menu row instead.  The messages the boot hook shows on the TV screen (a faster driver that didn't load, an adapter that couldn't become `eth0`, a hung adapter restarted) follow the app's language too: the app hands it to the script, which saves it with its settings, since those messages show at boot without the app.  A test checks that every status message the script can give has a translation.

### Fixed

- A long problem plus several tips could run the status card off the bottom of the screen, in English too.  The facts table tightens when there's something to say, the last log line steps aside, and tips that still don't fit are left off the screen (they're all in `status` and the report).

## [2.8.0] - 2026-11-07

### Added

- **The TV app speaks Russian.**  It follows the TV's menu language, and a new **Language** row picks one by hand (Auto, English, Русский), remembered on the TV.  Thanks to the [webos-forums.ru](https://webos-forums.ru/lg-usb-2-eth0-gigabit-usb-adapter-support-t9430.html) thread for the push.  What the script itself prints stays in English, and so do the GitHub reports, so their fields still match the forms.  Other languages are easy to add: see [Translating the app](README.md#translating-the-app).

### Changed

- With a lot of rows on screen (an update, Upgrade from v1 and a driver to test all at once), the menu squeezes a little more so the last row clears the footer.

## [2.7.4] - 2026-11-07

### Added

- **Drivers for 2018 LCDs on webOS 4.0.**  The LK61 (M3 chip, `4.4.84-404.glacier.10`) and UK62 to UK69 (LM18A chip, `4.4.84-636.glacier.26`) have no USB network driver at all.  Realtek (`r8152.ko` and `r8152_oot.ko`), ASIX AX88179 and Davicom DM9601, with a `usbnet.ko` loaded first, are waiting for testers.  Their firmware's kernel has no built-in config, so they're built with the release config in LG's source for the same kernel revision and checked against the TV's kernel image.

## [2.7.3] - 2026-11-07

### Added

- **Drivers for 2019 LCDs on webOS 4.5.**  The UM7000 to UM7800 (K5LP chip, kernels `4.4.84-p.649.grampians.k5lp.1` and `4.4.84-417.gld4tv.7`) already had throwaway96's Realtek and ASIX drivers in get-driver; now Realtek's newer `r8152_oot` (with 2.5G RTL8156), Davicom DM9601 and Microchip LAN78xx are waiting for testers too, built for each exact kernel.  The LM63 (M3R chip, `4.4.84-433`), whose kernel has no USB network driver at all, gets Realtek, ASIX AX88179 and Davicom, with a `usbnet.ko` loaded first.  Built from LG's webOS 4.5 source with configs that match the TVs' exactly, and waiting for testers.  webOS 4.5 TVs can be rooted with faultmanager-autoroot.
- **The firmware audit covers 29 more kernels**, back to webOS 3.5, from the firmware monitor's first full run.

## [2.7.2] - 2026-11-07

### Added

- **Drivers for the 2020 and 2021 8K and Mini LED LCDs.**  The 2020 NANO97, NANO99 and ZX 8K models (O208K chip, kernel `4.4.84-219.jcl4tvmr.6`) and the 2021 NANO96 to NANO99 and QNED90 to QNED99 (E60N chip, kernel `4.4.84-229.kcl4tv.6`) run the CX's and C1's kernel names, but without their Realtek and ASIX drivers.  Realtek (`r8152.ko` and `r8152_oot.ko`), ASIX AX88179, Davicom DM9601 and Microchip LAN78xx, built from LG's own kernel source with each TV's config, are waiting for testers.  A CX or C1 isn't offered them: drivers match by kernel and chip.
- **A firmware monitor.**  A daily workflow reads the [EPK archive](https://tv.slada.sk/)'s firmware index, audits the firmware of any new kernel this project doesn't cover yet and opens a `new-firmware` issue saying what it has and what needs building.  See [Watching for new firmware](docs/firmware-audit.md#watching-for-new-firmware).

## [2.7.1] - 2026-11-07

### Added

- **Drivers for 2021 LCD TVs with the K7LP chip** (UP and NANO models on firmware 03.53.46, webOS 6, kernel `4.4.84-723.kcl4tv.20`).  Realtek (`r8152.ko` and `r8152_oot.ko`), ASIX AX88179, Davicom DM9601 and Microchip LAN78xx, built from LG's KLP source with the TV's own config.  They're waiting for testers: **Test a new driver** in the app tries one.

## [2.7.0] - 2026-11-07

### Added

- **A hung adapter restarts itself.**  With `--watch` (**Follow plug and unplug** in the app), when the cable link is up and the TV keeps sending but nothing has come back for a minute, the adapter is re-plugged in software, as after standby, and made `eth0` again.  At most once every 30 minutes, so a dead router upstream can't cause a loop.  DonZoomik saw Realtek adapters stall like this on LG's USB controller; before, only a reboot fixed it.
- **A message on the TV screen when the boot switch goes wrong:** when the faster driver doesn't fit the kernel after a firmware update, when the adapter couldn't be made `eth0`, or when a hung adapter was restarted.  Nothing shows when it works.
- **Speed test history.**  The app shows your earlier results under a new one, with the driver each ran on, so a firmware or driver change shows up in the numbers.  The last 10 are kept across reboots; `speedtest` lists them too, and `status --json` has `speedHistory`.
- **Turning the TV on over the network.**  Standby resets the TV's USB ports, so the adapter can't be counted on to wake it.  Once the adapter is `eth0`, `status` says what can (Wi-Fi, or the built-in port if it has a cable) and which MAC to send the wake-up to, and the report has a `Wake over network` line.  The README's FAQ explains it, including for Home Assistant.

## [2.6.6] - 2026-11-07

### Fixed

- **The report and Test a new driver know the firmware and model when the app runs the script.**  Under the Homebrew Channel, the script's own `nyx-cmd` and `luna-send` can come back empty (a UN7300 on webOS 5 reported "Firmware: unknown", [#6](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/6)).  The app now asks the TV for its model, firmware and board type itself and passes them on.  The script only uses them when its own sources come up empty, and only if they're plain names and version numbers.  The board type (like `K6LP_ATSC_US`) is one more way to find the chip.
- **`status` and the report list a built-in port that shows up as a virtual device**, like the UN7300's once it's parked as `eth2` (its driver shows as `virtual`).

## [2.6.5] - 2026-11-07

### Added

- **`r8152_oot` for kernel `5.4.268-320` is tested:** tirth0jain reported it working on a 2024 G4 (OLED65G46LA) on webOS 24 ([#8](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/8)).  It moves to **Faster driver**.  What it adds there is RTL8156 (2.5G) support: an RTL8153 already runs at the same speed on the TV's own `r8152` (about 290 Mbit/s both ways, the USB 2.0 port's limit).  297 drivers are still waiting for testers.
- **The README lists the G4 with an RTL8153** ([#7](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/7)): 293 Mbit/s down, 285 up.

### Fixed

- **The driver test tests use a made-up kernel,** so promoting a real driver (as the promote workflow does) no longer breaks them.

## [2.6.4] - 2026-11-06

### Fixed

- **Switch now works on TVs whose built-in port has no parent device.**  On a 2020 UN7300 (55UN7300AUD) on webOS 5 ([#6](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/6)), LG's own Ethernet driver registers the built-in port as a virtual `eth0`.  The script didn't count that as the built-in port, so **Switch now** said "eth0 is not the built-in port", **Turn everything off** found no built-in port, and the report left it out.  A virtual `ethN` that's a plain Ethernet device now counts as the built-in port.  Bridges, bonds and tunnels still don't.

## [2.6.3] - 2026-11-06

### Added

- **The first driver built here that a tester reported working:** the K6Lp `r8152` for kernel `4.4.84-612.jcl4tv.40`, on a 2020 UN7300 (55UN7300AUD) with a Cable Matters RTL8153 adapter ([#6](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/6)): gigabit link and online on the first test.  It moves to **Faster driver**, so `get-driver` and the app offer it to every UN7300 on that kernel.  298 drivers are still waiting for testers.

## [2.6.2] - 2026-11-06

### Added

- **Drivers to test for LG's StanbyME** (27ART10AKPL, the rolling-stand screen, LM21UT chip) on webOS 24, kernel `5.4.268-955.16.nbr4tv.nmrm.10`: Realtek, ASIX AX88179, Davicom DM9601 and Aquantia AQC111, with the kernel's own `usbnet`.  LG lists its webOS 24 LMANN source for the StanbyME, which is a slightly later revision (`-966`) than its kernel, so these are a close match rather than the exact source.  The config and every symbol used check out against the StanbyME's own kernel.  299 drivers are now waiting for testers.

## [2.6.1] - 2026-11-06

### Fixed

- **Test a new driver shows up on TVs that don't report their chip through `nyx-cmd`.**  On a 2020 UN7300 on webOS 5 ([#6](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/6)) it named the chip over SSH but answered nothing when the app ran the script, so drivers built for its chip (K6Lp) weren't offered there and the row disappeared once the app loaded.  The script now falls back to the chip name LG's firmware keeps in `/etc/prefs/properties/machineName`, which is built per chip.  The report's `Chip:` line uses it too.

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
