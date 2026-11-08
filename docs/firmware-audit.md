# Firmware audit: USB Ethernet drivers in LG's firmware

Which USB Ethernet drivers each LG TV's kernel has, read straight from LG's own firmware files rather than from user reports.  It tells us which TVs work out of the box, which need a driver `get-driver` already offers, and which still need one built.

Last run: November 7, 2026, on the latest US firmware for each model, plus LG's LM21A-family LCD chips and the 2024 and 2025 OLED chips from the [EPK firmware archive](https://tv.slada.sk/).  The raw data is in [`scripts/firmware-audit/results.tsv`](../scripts/firmware-audit/results.tsv).

## Results

"Kernel" is what `uname -r` prints on that TV, which is what `get-driver` matches on.  "Built in" is the USB network drivers compiled into the kernel.  None of these firmwares ship any of them as loadable modules.

| Model | Year | Firmware | webOS | Chip | Kernel | Built in |
|-------|------|----------|-------|------|--------|----------|
| OLED65C9PUA | 2019 | 05.50.00 | 4.5 | o18 | `4.4.84-169.gld4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 55SM8600PUA (and the 2019 SM8500 to SM9800 NanoCells and B9) | 2019 | 05.50.00 | 4.5 | m16p3 | `4.4.84-169.gld4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65CXPUA | 2020 | 04.64.00 | 5 | o20 | `4.4.84-219.jcl4tvmr.6` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 75NANO99UNA (and the NANO97 and ZX 8K models) | 2020 | 04.64.00 | 5 | o208k | `4.4.84-219.jcl4tvmr.6` | asix only |
| 55UN7300PUF | 2020 | 04.64.00 | 5 | k6lp | `4.4.84-612.40.jimna.1` | asix only |
| OLED65C1PUB | 2021 | 03.53.45 | 6 | o20n | `4.4.84-229.kcl4tv.6` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 65QNED99UPA (and the 2021 NANO96 to NANO99 and QNED90 to QNED99) | 2021 | 03.53.45 | 6 | e60n | `4.4.84-229.kcl4tv.6` | asix only |
| 65NANO75UQA | 2022 | 04.60.92 | 22 | k8lp | `5.4.96-115.30.mole.2` | asix only |
| OLED65C2PUA | 2022 | 33.31.68 | 25 | o22 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C3PUA | 2023 | 33.31.68 | 25 | o22n | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 65UR9000PUA | 2023 | 33.31.75 | 25 | m23 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C4PUA | 2024 | 33.31.69 | 25 | o22n2 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65B4PUA (and 65QNED85TUA, same file) | 2024 | 33.31.75 | 25 | k24 | `5.4.268-294.24.papikonda.2` | asix only |
| OLED65B5PUA | 2025 | 33.31.75 | 25 | k24n | `5.4.268-294.24.papikonda.2` | r8152, asix |
| 75UQ9000PUD (and 2022 UQ70 to UQ90 models) | 2022 | 04.60.90 | 22 | lm21an | `5.4.96-934.mlt4tv.17` | **none, not even `usbnet`** |
| 70UQ8000AUB | 2022 | 04.54.40 | 22 | lm21an | `5.4.96-934.16.1.mirima.1` | **none, not even `usbnet`** |
| 2023 UR73 to UR81 (contributed firmware) | 2023 | 13.40.90 | 23 | lm21ann | `5.4.96-955.20.namtok.1` | **none, not even `usbnet`** |
| 2023 UR73 to UR81 (contributed firmware) | 2023 | 23.25.60 | 24 | lm21ann | `5.4.268-966.8.4.okapi.pine.1` | **none, not even `usbnet`** |
| 2023 UR73 to UR81 (contributed firmware) | 2023 | 33.22.59 | 25 | lm21ann | `5.4.268-966.15.ptl4tv.8` | **none, not even `usbnet`** |
| 27ART10AKPL (StanbyME, the rolling-stand screen) | 2022 | 23.22.86 | 24 | lm21ut | `5.4.268-955.16.nbr4tv.nmrm.10` | **none, not even `usbnet`** |
| 2021 UP and NANO LCDs (LM21A) | 2021 | 03.53.45 | 6 | lm21a | `4.4.84-899.19.koli.1` | **none, not even `usbnet`** |
| 2021 LCDs with the LM21U chip | 2021 | 03.41.05 | 6 | lm21u | `4.4.84-899.kcl4tv.19` | **none, not even `usbnet`** |
| OLED65G4SUB | 2024 | 03.11.20 | 24 | o24 | `5.4.96-314` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65G4SUB | 2024 | 33.31.69 | 25 | o24 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65G5WUA | 2025 | 33.31.69 | 25 | o24n | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C5PUA (and 65QNED9MAUA, same file) | 2025 | 33.31.69 | 25 | o22n3 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED55G6WUA (and the 2026 C6) | 2026 | 43.11.81 | 26 | o26 | `6.12.44-347` | r8152, r8153_ecm, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65B6GUA | 2026 | 43.21.88 | 26 | k26 | `6.12.44-67.18.qilian.5` | r8152, asix |
| OLED55G6WUA (and the 2026 C6) | 2026 | 43.21.69 | 26 | o26 | `6.12.44-352` | r8152, r8153_ecm, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED B4 (and QNED85, same file) | 2024 | 43.22.72 | 26 | k24 | `6.12.44-67.18.qilian.6` | asix only |
| OLED B5 | 2025 | 43.22.72 | 26 | k24n | `6.12.44-67.18.qilian.6` | asix only |
| 2024 UT81 and QNED80T | 2024 | 43.22.13 | 26 | k8lpn2 | `6.12.44-67.18.qilian.5` | asix only |
| 2021 LCDs with the K7LP chip | 2021 | 03.53.46 | 6 | k7lp | `4.4.84-723.kcl4tv.20` | asix only |
| 65QNED7SBUA | 2026 | 43.21.87 | 26 | k25lpnlm | `6.12.44-67.18.qilian.5` | asix only |
| OLED65C2PUA | 2022 | 43.21.94 | 26 | o22 | `6.12.44-352` | r8152, r8153_ecm, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C4PUA | 2024 | 43.21.96 | 26 | o22n2 | `6.12.44-352` | r8152, r8153_ecm, asix, ax88179_178a, cdc_ether, cdc_ncm |

## What it tells us

- **LG's LM21A-family LCD chips have no USB network drivers at all.**  The 2021 UP and NANO (LM21A, LM21U, on 4.4 kernels), 2022 UQ (LM21AN), 2023 UR (LM21ANN) and StanbyME (LM21UT) kernels leave out `usbnet` itself, the core every USB Ethernet driver builds on, so no USB adapter works on them, whatever its chip.  Drivers built from LG's published source are now [waiting for testers](../README.md#more-drivers-on-the-way) for the UP and NANO on webOS 6, the UQ on webOS 22, the UR on webOS 23 to 25 and the StanbyME on webOS 24: Realtek on its own, and ASIX AX88179, Davicom and (on 5.4) Aquantia with the kernel's own `usbnet.ko`, which the script loads first.
- **No LG kernel has `aqc111`, `dm9601` or `lan78xx`,** not even LG's own OLED chips, so Aquantia AQC111/AQC112, Davicom DM9601 and Microchip LAN78xx adapters get no driver on any LG TV.  Builds to test are in [More drivers on the way](../README.md#more-drivers-on-the-way).
- **The 2024 and 2025 OLED chips (O24, O24N, O22N3) run the C2's kernel,** `5.4.268-329.ptl4tv.5`, with the same config, so DonZoomik's `r8152_oot` covers the G4, G5 and C5 too.
- **One kernel covers most LG chips on webOS 25.**  The C2, C3, C4 and the UR9000 LCD all run `5.4.268-329.ptl4tv.5`, so DonZoomik's `r8152_oot` fits all of them.  Their built-in `r8152` is too old for newer Realtek chips, which is why those adapters end up on `cdc_ncm`.
- **2024 and 2025 Realtek-chip TVs (K24, K24N) need help.**  On current firmware the B4 and QNED85 have no Realtek driver and no ASIX AX88179 driver at all, and the B5 has only an old built-in `r8152`.  None of them has `cdc_ncm`, so a 2.5G RTL8156 adapter gets no driver on any of them.
  - dd3git's `ax88179_178a` is built for exactly this kernel, so `get-driver` already offers it on the B4 and QNED85 as well as the B5.
  - mbenitez343's `r8152` is for `5.4.268-294.17.paparoa.pine.2`, an older kernel for these TVs.  On current firmware they report `294.24.papikonda.2` instead, so it's no longer offered there.  **An `r8152` for `5.4.268-294.24.papikonda.2` is the most useful driver still missing.**
- **Older Realtek-chip LCD TVs have only the ASIX AX8817x driver.**  The 2020 UN7300 (K6LP) and 2022 NANO75 (K8LP) have no `r8152`, no `ax88179_178a` and no `cdc_ncm`.  An adapter needs a module built for them.
  - The UN7300's current firmware reports `4.4.84-612.40.jimna.1`, not the `4.4.84-612.jcl4tv.40` that OCT0PUSCRIME's driver was built for.  That kernel name may come from older firmware, so his module may not load after an update.  A report from a UN7300 on 04.64.00 would settle it.  For that kernel, and K6Lp's `4.4.84-612.21.6.jardine.2`, there are now Realtek and ASIX drivers to test, built with the TV's own config: see [driver-build.md](driver-build.md).
- **Older budget LCDs mostly have nothing useful.**  The archive's older firmware, checked by the [firmware monitor](#watching-for-new-firmware): the 2019 UM7000 to UM7800 (K5LP) and 2017 UJ63 (K3LP) have only `asix`; the 2019 LM63 (M3R), 2018 LK61 (M3), 2018 UK62 to UK69 (LM18A) and 2017 LJ (M2R) have no USB network driver at all.  The 2017 and 2018 OLEDs and NanoCells (M16P, M16PP, O18 on webOS 3.5 and 4.0) have `r8152` but no ASIX driver, and no `usbnet`.  All of these lines are in [`results.tsv`](../scripts/firmware-audit/results.tsv).  webOS 4.0 and 4.5 TVs can still be rooted with [faultmanager-autoroot](https://github.com/throwaway96/faultmanager-autoroot), so the most common of them now have drivers to test: the UM7000 to UM7800 (K5LP, on both its 05.00 and 05.40 kernels, adding RTL8156, Davicom and Microchip to throwaway96's Realtek and ASIX drivers) and the LM63 (M3R, with a `usbnet.ko`, on both its 05.00 and 05.40 kernels), built from LG's webOS 4.5 source with configs that match the TVs' exactly.  The 2018 LK61 (M3) and UK62 to UK69 (LM18A) have them too, with a `usbnet.ko`, and so does the 2017 UJ63 (K3LP, kernel `4.4.3-208.drd4tv.3`): Realtek, ASIX AX88179, Davicom and Microchip, built from LG's webOS 3.5 DKLP3 source with the firmware's own config.  The 2017 LJ (M2R, kernel `4.4.3-78.drd4tv.2`) has Realtek, ASIX AX88179 and Davicom with a `usbnet.ko`, built from LG's webOS 3.5 DMR source with its `m2r_defconfig`, since that firmware's kernel has no built-in config either.  Their firmware's kernel has no built-in config, so those are built with the release `.config` that ships in LG's source for the same kernel revision (404 and 636), and checked against each TV's kernel image and its own modules' vermagic.  The 2018 OLEDs, NanoCells and UK LCDs on `4.4.84-150.glacier.2` (O18, M16PP, M16PP LITE) have drivers to test too: RTL8156, ASIX AX88179, Davicom and Microchip with a `usbnet.ko`, one build for all three chips, built from LG's webOS 4.0 source with the firmware's own config (O18 and M16PP have the same one).
- **LG's own OLED chips (O18 to O22N2) have everything built in** on webOS 4.5 to 25.  Adapters work out of the box there.  Only the driver version decides how fast.
- **The 2020 and 2021 8K and Mini LED LCDs don't.**  The 2020 NANO97, NANO99 and ZX (O208K) run the CX's kernel name, `4.4.84-219.jcl4tvmr.6`, and the 2021 NANO96 to NANO99 and QNED90 to QNED99 (E60N) run the C1's, `4.4.84-229.kcl4tv.6`, but their chips' configs have only `asix` and `usbnet`: no Realtek and no AX88179.  Same kernel name, different drivers, which is why the script matches drivers by kernel and chip.  Realtek, ASIX AX88179, Davicom and Microchip drivers built from LG's own `linux-4.4-lg115x` source with each TV's config are waiting for testers for both.
- **webOS 26 moves to kernel 6.12, and on the 2026 models it only loads drivers LG signed.**  Their kernels have `MODULE_SIG_FORCE=y`, so no added driver can load, even as root: what's built in is all there is.  That goes by the chip, not the kernel name: the C6 and G6 moved from `6.12.44-347` to `6.12.44-352` in 43.21.69 and still enforce it, while the 2022 to 2025 OLEDs' `6.12.44-352` has signing off on every one of their chips (O22, O22N, O22N2, O22N3, O24, O24N, checked on 43.21.71 to 43.21.96).  Likewise `6.12.44-67.18.qilian.5` enforces it on the B6 and QNED7S but not on the K8LpN2 LCDs, and the B4 and B5's `qilian.6` has it off.  So the script checks the running kernel (`sig_enforce`) instead of trusting a kernel name.  Where the built-in drivers are enough, adapters work once the TV is rooted:
  - LG's own chips (the 2022 to 2025 OLEDs on `6.12.44-352`, and the 2026 C6 and G6 on `6.12.44-347`) have everything built in.  Their `r8152` handles RTL8153 and RTL8156 properly, and `r8153_ecm` is there too.
  - The 2026 B6 (K26) has `r8152` and `asix` but no `ax88179_178a`, so AX88179 adapters get nothing.  The 2026 QNED7S (K25LpNLM) has only `asix`: no Realtek and no AX88179.  Neither can be fixed with a driver.
  - Root: webOS 26 firmware released after October 10, 2026 (like 43.21.84) is patched, per the [EPK archive's rooting guide](https://tv.slada.sk/guides/rooting-guide).  Earlier webOS 26 firmware, like the 2026 models' launch firmware, can still be rooted.

## How it works

[`scripts/firmware-audit/audit.sh`](../scripts/firmware-audit/audit.sh) takes one firmware `.zip` (or `.epk`) from LG's support site:

1. Unpacks it with [epk2extract](https://github.com/openlgtv/epk2extract) from openlgtv, which has the decryption keys for most LG chips.
2. If the firmware has a kernel image, `kernel-info.py` reads its version string and the config built into it, which says driver by driver whether it's built in, a module, or missing.  Newer firmware keeps the kernel inside the root filesystem, as `boot/Image.lz4-<kernel>` in LG's LZ4P format, and 2020 Realtek-chip TVs ship a U-Boot image around a self-unpacking ARM zImage.  It reads both.
3. Some updates have neither.  Then it reads `lib/modules/<kernel>/modules.builtin` from the root filesystem instead (`usr/lib/modules` on webOS 26).
4. It prints one line for `results.tsv`, and deletes the firmware and everything it unpacked.

```sh
git clone https://github.com/openlgtv/epk2extract && (cd epk2extract && ./build.sh)
EPK2EXTRACT=$PWD/epk2extract/build_linux/epk2extract scripts/firmware-audit/audit.sh firmware.zip OLED65C2PUA
```

It needs `unsquashfs` (squashfs-tools) and python3.  A firmware file is 1 to 2 GB, so it only keeps one at a time.  With `SAVE=DIR` it also keeps the kernel image and its config in `DIR/<kernel>/`, for [building a driver](driver-build.md) against that kernel.

The download links for current firmware are on each model's LG support page (Manuals & Software, Download Software).  LG only keeps the latest one, so older firmware comes from the [EPK firmware archive](https://tv.slada.sk/).  Its [`processed_fw.json`](https://tv.slada.sk/processed_fw.json) lists the exact kernel of every firmware it has (`kernelVersion`), so you can find which firmware runs a kernel without downloading anything.  Please try LG's download first, and keep to two downloads at a time there.

## Watching for new firmware

A [daily workflow](../.github/workflows/firmware-monitor.yml) reads the archive's `processed_fw.json` and looks for (kernel, chip) pairs that are new: no drivers in the script and no row in `results.tsv`.  For each one (up to three a day), it downloads the newest firmware with it, runs `audit.sh` on it and opens an issue labeled [`new-firmware`](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues?q=label%3Anew-firmware) that says what the kernel has: drivers built in, module signing enforced, or what needs building.  The run's summary has the whole coverage table, every LG kernel from 4.4 on with what the project has for it.  [`monitor.py`](../scripts/firmware-audit/monitor.py) does the comparing, and runs locally too:

```sh
python3 scripts/firmware-audit/monitor.py coverage -     # the table, from the live index
python3 scripts/firmware-audit/monitor.py new - 2026-10-01   # new kernels since a date
```

Want a model added?  Open an issue with its model number.
