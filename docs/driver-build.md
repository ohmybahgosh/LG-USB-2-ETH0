# Building drivers for more LG kernels

`get-driver` can only offer a driver someone built for the exact kernel a TV runs.  Most kernels have none, so this is how we build them ourselves, and which ones are built so far.  **None of the drivers below is offered yet:** each needs someone with that TV to try it first.  If yours is one of them, see [Testing one](#testing-one).

## The method

It's [DonZoomik's](https://github.com/DonZoomik/webos-r8152), whose `r8152_oot.ko` works on 2022 to 2024 OLEDs on kernel `5.4.268-329.ptl4tv.5`, made repeatable:

1. **The kernel source.**  LG publishes each model's kernel on [LG Open Source](https://opensource.lge.com/) (search the model, then the webOS release).  A kernel module only needs the headers and build system, so only the kernel part of the package is used.
2. **The kernel's exact config.**  LG builds it into the kernel (`CONFIG_IKCONFIG`).  `scripts/firmware-audit/audit.sh` with `SAVE=DIR` pulls the kernel image out of a firmware file and saves the image and its config.  Older firmware comes from the [EPK firmware archive](https://tv.slada.sk/), whose `processed_fw.json` lists the exact kernel of every firmware it has.
3. **Build** with the TV's kernel name as the version suffix, so the module's `vermagic` matches exactly.
4. **Check**, and keep the module only if:
   - its `vermagic` is exactly the kernel's,
   - the kernel has `MODVERSIONS` off (true for every LG kernel so far), so there are no symbol CRCs to match, and no module signing either,
   - every symbol it imports is exported by that kernel image,
   - on kernels for LG's own chips (o22 family) with 5.4.268, the USB struct offsets the driver relies on match the ones DonZoomik measured on a real TV.  Elsewhere the layout depends on that chip's config, so the module is reported as "struct offsets unchecked".

`scripts/driver-build/build.sh` does steps 3 and 4:

```sh
# Cross compilers: aarch64-linux-gnu-gcc and arm-linux-gnueabihf-gcc
git clone https://github.com/DonZoomik/webos-r8152
DRIVER_SRC=$PWD/webos-r8152 scripts/driver-build/build.sh \
    kernels/5.4.268-329.ptl4tv.2 path/to/linux-rockhopper r8152 out
```

It prints one line: the kernel, the module, its SHA-256 and the checks.  Realtek-chip sources (K24 and others) also need `CHIP_NAME` (like `k24`) and LG's `drivers/rtk_kdriver` tree, or empty `drivers/rtk_kdriver/common_header/CHIP/include` and `drivers/rtk_kdriver/common_header/rbus/CHIP` folders in its place (r8152 uses nothing from it).

**The method is checked:** built from LG's published C2 source with the TV's config, DonZoomik's driver for `5.4.268-329.ptl4tv.5` comes out the same as his working module: same `vermagic`, same source version, the same 128 imported symbols and 108 adapter IDs.

## Built so far

All are Realtek's r8152 v2.22.1 as DonZoomik patched it, named `r8152_oot` so it can sit next to an old built-in `r8152`.  It covers RTL8152, RTL8153 (gigabit) and RTL8156 (2.5 gigabit) adapters.

| Kernel | TVs (from the firmware archive) | LG source used | Struct offsets |
| --- | --- | --- | --- |
| `5.4.268-329.ptl4tv.2` | 2022 to 2025 OLEDs (o22 family) on firmware 33.20 to 33.23, 67 firmware files | webOS25 WG ReNew (C2), kernel 324 | checked |
| `5.4.268-320` | 2022 to 2024 OLEDs on webOS 23 firmware 23.20 to 23.25, 38 files | webOS25 WG ReNew (C2), kernel 324 | checked |
| `5.4.96-307` | 2022 and 2023 OLEDs on firmware 03.31, 03.33 and 13.30, 19 files | webOS 23 O ReNew (C2), `linux-5.4-lg115x` | unchecked |
| `5.4.268-294.24.papikonda.2`, K24 chip only | 2024 and 2025 TVs with the K24 chip on firmware 33.31, 17 files | webOS25 WH ReNew (B4), `kernel-294.ptl4tv.2` | unchecked |

The K24 one matters most: those kernels have no Realtek driver built in at all, not even an old one, so a Realtek adapter doesn't work on them today.

## What we learned

- **One kernel name can mean several configs.**  `5.4.268-294.24.papikonda.2` runs on seven Realtek chips (K24, K24N, K25Lp, K8Hp, K8Hpp, K8LpN, K8LpN2), and their configs differ in about 100 options: K24 has no Realtek driver, K8Hpp has an old one.  A driver for that kernel name has to be picked by chip too, as `get-driver` already does for K5Lp.
- **Struct layouts differ between chips**, even with the same kernel source: `struct device` (inside `struct usb_device`) grows or shrinks with options like `PINCTRL`.  So a module is only right for the chip whose config it was built with.
- **Newer firmware carries the kernel inside the rootfs**, as `boot/Image.lz4-<kernel>` in LG's LZ4P container (a 32-byte header, a table of block lengths, then raw LZ4 blocks).  `kernel-info.py` unpacks it.
- **LG's packages are laid out differently each year.**  webOS 25 packages have `soc_*/linux-and-kdriver_*.tar.gz` (LG's chips) or `soc_*/kernel-*.tar.gz` (Realtek's).  The webOS 23 C2 package has `chipset/SIC_O22_webOS23.zip`, with the kernel inside `kdriver.tar` as `kdriver/kernel/linux-5.4-lg115x.tgz`.

## Next

- Testers for each driver above.
- The other six papikonda.2 chips, which need LG's source for a model with that chip.
- `ax88179_178a` for kernels that lack it (K24 already has dd3git's).
- 2020 and 2021 kernels (`4.4.84-219.jcl4tvmr.6` on CX OLEDs, `4.4.84-229.kcl4tv.6`), which need older LG source.

## Testing one

If your TV runs one of the kernels above (`uname -r` over SSH, or the first lines of `report`) and you have a Realtek USB adapter, say so in the [discussions](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions).  The test is short: copy the module to the TV, `insmod` it, plug in the adapter and check it comes up.  A driver that doesn't fit can at worst freeze or crash the TV until it restarts (unplug it if it doesn't on its own).  Nothing loads the driver again unless you do, so the TV comes back as it was.
