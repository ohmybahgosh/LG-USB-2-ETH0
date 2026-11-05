# Firmware audit: USB Ethernet drivers in LG's firmware

Which USB Ethernet drivers each LG TV's kernel has, read straight from LG's own firmware files rather than from user reports.  It tells us which TVs work out of the box, which need a driver `get-driver` already offers, and which still need one built.

Last run: November 5, 2026, on the latest US firmware for each model.  The raw data is in [`scripts/firmware-audit/results.tsv`](../scripts/firmware-audit/results.tsv).

## Results

"Kernel" is what `uname -r` prints on that TV, which is what `get-driver` matches on.  "Built in" is the USB network drivers compiled into the kernel.  None of these firmwares ship any of them as loadable modules.

| Model | Year | Firmware | webOS | Chip | Kernel | Built in |
|-------|------|----------|-------|------|--------|----------|
| OLED65C9PUA | 2019 | 05.50.00 | 4.5 | o18 | `4.4.84-169.gld4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65CXPUA | 2020 | 04.64.00 | 5 | o20 | `4.4.84-219.jcl4tvmr.6` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 55UN7300PUF | 2020 | 04.64.00 | 5 | k6lp | `4.4.84-612.40.jimna.1` | asix only |
| OLED65C1PUB | 2021 | 03.53.45 | 6 | o20n | `4.4.84-229.kcl4tv.6` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 65NANO75UQA | 2022 | 04.60.92 | 22 | k8lp | `5.4.96-115.30.mole.2` | asix only |
| OLED65C2PUA | 2022 | 33.31.68 | 25 | o22 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C3PUA | 2023 | 33.31.68 | 25 | o22n | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| 65UR9000PUA | 2023 | 33.31.75 | 25 | m23 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C4PUA | 2024 | 33.31.69 | 25 | o22n2 | `5.4.268-329.ptl4tv.5` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65B4PUA (and 65QNED85TUA, same file) | 2024 | 33.31.75 | 25 | k24 | `5.4.268-294.24.papikonda.2` | asix only |
| OLED65B5PUA | 2025 | 33.31.75 | 25 | k24n | `5.4.268-294.24.papikonda.2` | r8152, asix |
| OLED65C2PUA | 2022 | 43.21.94 | 26 | o22 | `6.12.44-352` | r8152, r8153_ecm, asix, ax88179_178a, cdc_ether, cdc_ncm |
| OLED65C4PUA | 2024 | 43.21.96 | 26 | o22n2 | `6.12.44-352` | r8152, asix, ax88179_178a, cdc_ether, cdc_ncm |

## What it tells us

- **One kernel covers most LG chips on webOS 25.**  The C2, C3, C4 and the UR9000 LCD all run `5.4.268-329.ptl4tv.5`, so DonZoomik's `r8152_oot` fits all of them.  Their built-in `r8152` is too old for newer Realtek chips, which is why those adapters end up on `cdc_ncm`.
- **2024 and 2025 Realtek-chip TVs (K24, K24N) need help.**  On current firmware the B4 and QNED85 have no Realtek driver and no ASIX AX88179 driver at all, and the B5 has only an old built-in `r8152`.  None of them has `cdc_ncm`, so a 2.5G RTL8156 adapter gets no driver on any of them.
  - dd3git's `ax88179_178a` is built for exactly this kernel, so `get-driver` already offers it on the B4 and QNED85 as well as the B5.
  - mbenitez343's `r8152` is for `5.4.268-294.17.paparoa.pine.2`, an older kernel for these TVs.  On current firmware they report `294.24.papikonda.2` instead, so it's no longer offered there.  **An `r8152` for `5.4.268-294.24.papikonda.2` is the most useful driver still missing.**
- **Older Realtek-chip LCD TVs have only the ASIX AX8817x driver.**  The 2020 UN7300 (K6LP) and 2022 NANO75 (K8LP) have no `r8152`, no `ax88179_178a` and no `cdc_ncm`.  An adapter needs a module built for them.
  - The UN7300's current firmware reports `4.4.84-612.40.jimna.1`, not the `4.4.84-612.jcl4tv.40` that OCT0PUSCRIME's driver was built for.  That kernel name may come from older firmware, so his module may not load after an update.  A report from a UN7300 on 04.64.00 would settle it.  For that kernel, and K6Lp's `4.4.84-612.21.6.jardine.2`, there are now Realtek and ASIX drivers to test, built with the TV's own config: see [driver-build.md](driver-build.md).
- **LG's own OLED chips (O18 to O22N2) have everything built in** on webOS 4.5 to 25.  Adapters work out of the box there.  Only the driver version decides how fast.
- **webOS 26 moves to kernel 6.12** (`6.12.44-352`), whose built-in `r8152` handles RTL8153 and RTL8156 properly.  Root is patched there though, so it doesn't help rooted TVs: see the warning in the README.

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

Want a model added?  Open an issue with its model number.
