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

It prints one line: the kernel, the module, its SHA-256 and the checks.  On arm64 it also gives the 32-bit compat vDSO, built during kernel prep, the `-march=armv8-a` it needs (it isn't part of the module).  `intree:NAME` builds `drivers/net/usb/NAME.c` from LG's own source instead, for a kernel that leaves that driver out (like `intree:ax88179_178a` or `intree:r8152`).  Realtek-chip sources (K24 and others) also need `CHIP_NAME` (like `k24`) and LG's `drivers/rtk_kdriver` tree, or empty `drivers/rtk_kdriver/common_header/CHIP/include` and `drivers/rtk_kdriver/common_header/rbus/CHIP` folders in its place (r8152 uses nothing from it).

### 32-bit kernels (2020 and 2021 TVs)

webOS 5 and 6 TVs often run a 32-bit (ARMv7) kernel.  `build.sh` reads that from the config and builds for it, the way [OCT0PUSCRIME](https://github.com/OCT0PUSCRIME/lg-webos-ax88179-driver) built his ASIX driver for the 2020 UN7300 (his steps are in [discussion #3](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/3)).  These old 4.4 kernels need a few things with a current GCC, which `build.sh` handles:

- `-march=armv7-a`, since the old Makefiles don't pass the CPU to a new assembler,
- `HOSTCFLAGS=-fcommon` for their host tools,
- `cc-no-werror`, a compiler wrapper that drops `-Werror`, since parts of LG's and Realtek's code turn warnings a new GCC added into errors.

Their firmware carries the kernel as a U-Boot image around a self-unpacking zImage, which `kernel-info.py` unpacks to get the TV's own config and kernel.  Where a firmware doesn't have it, the config can come from LG's source (for the UN7300's K6Lp chip, `make ARCH=arm realtek/config.develop.rtd288o.tv006.emmc.old_defconfig`, as its `README_HowToMake.txt` says).  These kernels set `CONFIG_IKCONFIG_PROC`, so a TV's own config is in `/proc/config.gz` too.  To check exports without the TV's kernel image, build the whole kernel once and give `build.sh` its `Module.symvers` and a `release` file with the kernel name.  A full build of a 4.4 kernel also needs the old `#alloc` section flags in `arch/arm` assembly changed to `"a"` (and `#alloc, #execinstr` to `"ax"`), as upstream Linux later did.

**Checked against OCT0PUSCRIME's module:** LG's webOS 5 K6Lp source (`kernel-1.0.0-612.21`, from the "webOS 5.0 JKHP 2.0" package) built with its own config and his version suffix exports all 60 symbols his working `ax88179_178a.ko` imports.  Built from that tree, the kernel's own `ax88179_178a` and `r8152` come out with the same `vermagic` as his (`4.4.84-612.jcl4tv.40 SMP preempt mod_unload ARMv7`), and every symbol they import is exported.  DonZoomik's newer r8152 doesn't build on these kernels: LG backported newer kernel functions into 4.4, which confuses its compatibility checks.

**The method is checked:** built from LG's published C2 source with the TV's config, DonZoomik's driver for `5.4.268-329.ptl4tv.5` comes out the same as his working module: same `vermagic`, same source version, the same 128 imported symbols and 108 adapter IDs.

## Built so far

The 64-bit ones are Realtek's r8152 v2.22.1 as DonZoomik patched it, named `r8152_oot` so it can sit next to an old built-in `r8152`.  It covers RTL8152, RTL8153 (gigabit) and RTL8156 (2.5 gigabit) adapters.  The 32-bit ones are the kernel's own `r8152` (RTL8152 and RTL8153) and `ax88179_178a` (ASIX AX88179), which LG leaves out of those kernels.

| Kernel | TVs (from the firmware archive) | LG source used | Struct offsets |
| --- | --- | --- | --- |
| `5.4.268-329.ptl4tv.2` | 2022 to 2025 OLEDs (o22 family) on firmware 33.20 to 33.23, 67 firmware files | webOS25 WG ReNew (C2), kernel 324 | checked |
| `5.4.268-320` | 2022 to 2024 OLEDs on webOS 24 firmware 23.20 to 23.25, 38 files | webOS25 WG ReNew (C2), kernel 324 | checked |
| `5.4.96-307` | 2022 and 2023 OLEDs on firmware 03.31, 03.33 and 13.30, 19 files | webOS 23 O ReNew (C2), `linux-5.4-lg115x` | unchecked |
| `5.4.268-294.24.papikonda.2`, K24 chip only | 2024 and 2025 TVs with the K24 chip on firmware 33.31, 17 files | webOS25 WH ReNew (B4), `kernel-294.ptl4tv.2` | unchecked |

| `4.4.84-612.40.jimna.1`, K6Lp chip only | 2020 TVs with the K6Lp chip (like the UN7300) on current firmware 04.64, 22 files | webOS 5.0 JKHP 2.0 (UN7310), `kernel-1.0.0-612.21` | unchecked |
| `4.4.84-612.21.6.jardine.2`, K6Lp chip only | 2020 TVs with the K6Lp chip on firmware 03.21, 21 files | the same, which is `612.21.6.jardine.3`, one step from this kernel | unchecked |

| `5.4.268-294.24.papikonda.2`, per chip: K24N, K25Lp, K8Hp, K8Hpp, K8LpN, K8LpN2 | 2023 to 2025 LCDs and OLEDs with those Realtek chips on firmware 33.31, about 64 files | webOS25 WH ReNew (B4), `kernel-294.ptl4tv.2` | unchecked |
| `5.4.268-294.ptl4tv.24`, K24N and K25Lp (with `ax88179_178a` for K25Lp) | 2025 TVs on firmware 33.30, 18 files | the same | unchecked |
| `5.4.96-115.30.mole.2` and `5.4.96-115.28.mirima.1`, per chip: K8Hp, K8Lp, K8Ap (with `ax88179_178a`) | 2022 and 2023 LCDs (like the NANO75) on webOS 22 firmware 04.53 to 04.60, about 57 files | webOS 22 KLP_12.0 (55UQ8000), `kernel-1.0.0-114`, LG's real K8 source | unchecked |
| `5.4.96-115.16.mebbin.1`, `5.4.96-115.16.mebbin.2`, `5.4.96-115.22.meru.2`, `5.4.96-115.28.1.22.mirima.2` and `5.4.96-115.9.marine.1`, per chip: K8Lp, K8HpT, K8Ap (with `ax88179_178a`) | webOS 22 TVs on older firmware 03.21 to 04.54, 16 files | the same | unchecked |
| `5.4.96-132.40.nameri.2`, `5.4.96-132.40.nameri.pine.1` and `5.4.96-132.50.namtok.2`, per chip: K8Hp, K8Hpp, K8LpN (with `ax88179_178a`) | webOS 23 TVs on firmware 03.31, 13.30 and 13.41, 19 files | webOS 23 KHP+ 5.0 (65QNED80ARA), `kernel-1.0.0-nbr4tv.39`, the 132 kernels' own source | unchecked |
| `5.4.96-223.29.1.okapi.2`, `5.4.96-223.9.oeta.2` and `5.4.96-223.obr4tv.29`, K24 (and K8LpN2 for oeta.2), with `ax88179_178a` | 2024 TVs on their first webOS 24 firmware, 03.10, 03.11 and 23.20, 16 files | webOS 24 K 2.0 (55QNED85T3C), `kernel-223.obr4tv.4` | unchecked |
| `5.4.268-223.29.okapi.5`, `5.4.268-223.29.okapi.pine.4`, `5.4.268-223.42.okapi.nmrm.2` and `5.4.268-223.obr4tv.42`, per chip: K24, K24T, K8Hp, K8Hpp, K8HpT, K8LpN, K8LpN2 (with `ax88179_178a`) | webOS 24 TVs on firmware 23.21 to 23.25, including 2022 OLEDs (A2, B2) updated to webOS 24, 49 files | none published: webOS25 WH ReNew (B4), `kernel-294.ptl4tv.2`, the nearest 5.4.268 source | unchecked |

| `4.4.84-612.40.jimna.1` and `4.4.84-612.21.6.jardine.2`, K6Hp chip | 2020 TVs with the K6Hp chip (like the NANO87) on firmware 03.21, 04.63 and 04.64, 19 files | as for K6Lp: the K6Hp config is the same | unchecked |
| `4.4.84-611.japoon.14`, K6Lp chip | LG's HU810P projector on firmware 03.00 and 03.10, 3 files | the 612.21 source above | unchecked |

The K24 and K6Lp ones matter most: those kernels have no Realtek driver built in at all, not even an old one (the K6Lp ones have no `cdc_ncm` either), so a Realtek adapter doesn't work on them today.  The K6Lp kernels have no AX88179 driver either.

The webOS 22 K8 ones matter as much: those kernels have only `asix` built in, so neither a Realtek adapter nor an AX88179 works on a 2022 NANO75 today.  On papikonda.2, ASIX adapters already have dd3git's driver: the config options that shape shared structs (`REALTEK_SCHED_LOG`, `REALTEK_MEMORY_MANAGEMENT`, `NR_CPUS`, `PREEMPT` and others) are the same on every chip that runs it, so only the Realtek driver is built per chip there.

**When the source is missing part of the config.**  The B4's source has machine support for K24 and K25 only, not K8, and no `rtk_kdriver` tree.  Options the TV's config has but the source doesn't define are dropped, which is harmless unless a kernel header uses one: on K8, `REALTEK_SCHED_LOG` changes `struct thread_info` and `REALTEK_MEMORY_MANAGEMENT` changes page flags, so a module built without them would use the wrong layout.  `build.sh` now stops when that happens and names the options.  `kconfig-stub.py` then writes their Kconfig from the TV's own config (into the missing `arch/arm64/mach-k8/Kconfig` here), so every one keeps the TV's value, and the build config comes out the same as the TV's.

**How the K6Lp builds were checked without a tester:** their firmware does carry the kernel, as a U-Boot image around a self-unpacking ARM zImage, with the config built in.  `kernel-info.py` unpacks that now, so each was built with the TV's own config and checked against the TV's own kernel: every option in the config exists in LG's source, the module's `vermagic` flags are the same as LG's own modules for that kernel (`SMP preempt mod_unload ARMv7`), and every symbol it imports is in the TV's kernel.  For jimna.1, whose source LG hasn't published (it's revision 612.40, the source 612.21), a full build of the 612.21 source with jimna.1's config exports 8,447 symbols, and all but 98 are in the real kernel.  The 98 are LG's TV tuner code (`KHAL_DEMOD_*`), which a network driver doesn't use.

## What we learned

- **One kernel name can mean several configs.**  `5.4.268-294.24.papikonda.2` runs on seven Realtek chips (K24, K24N, K25Lp, K8Hp, K8Hpp, K8LpN, K8LpN2), and their configs differ in about 100 options: K24 has no Realtek driver, K8Hpp has an old one.  A driver for that kernel name has to be picked by chip too, as `get-driver` already does for K5Lp.
- **Struct layouts differ between chips**, even with the same kernel source: `struct device` (inside `struct usb_device`) grows or shrinks with options like `PINCTRL`.  So a module is only right for the chip whose config it was built with.
- **Newer firmware carries the kernel inside the rootfs**, as `boot/Image.lz4-<kernel>` in LG's LZ4P container (a 32-byte header, a table of block lengths, then raw LZ4 blocks).  `kernel-info.py` unpacks it.
- **Firmware 23.xx is webOS 24**, not webOS 23: the platform version inside each EPK says so (9.x is webOS 24, 8.x webOS 23, 7.x webOS 22).  The first webOS 24 firmware (03.1x and 23.20) runs 223 kernels on 5.4.96, later ones on 5.4.268.
- **LG hasn't published every kernel.**  Its webOS 24 packages all hold `kernel-223.obr4tv.4` on 5.4.96, so the 223 kernels on 5.4.268 are built from the webOS 25 source (294), the nearest 5.4.268 tree.  LG's own header changes between those branches are config-gated or prototype-only for what a USB network driver uses, and `build.sh` now lists any config option the source adds or changes that a kernel header uses (here only `GENERIC_IRQ_IPI`, which these drivers never touch).
- **TVs with LG's own chips on kernel 4.4 already have both drivers.**  The 2020 CX (`4.4.84-219.jcl4tvmr.6`, o20 and o208k) and 2021 TVs on `4.4.84-229.kcl4tv.6` (e60n) build `r8152` and `ax88179_178a` into the kernel, so there's nothing to add there.  DonZoomik's `r8152` v2.22.1 (for RTL8156) doesn't compile on 4.4 without porting.
- **Some LG source trees ship already configured** (a `.config` and generated headers in the tree, like the webOS 5.0 JO package), which a separate build folder refuses.  Move them aside first.
- **LG's packages are laid out differently each year.**  webOS 25 packages have `soc_*/linux-and-kdriver_*.tar.gz` (LG's chips) or `soc_*/kernel-*.tar.gz` (Realtek's).  The webOS 23 C2 package has `chipset/SIC_O22_webOS23.zip`, with the kernel inside `kdriver.tar` as `kdriver/kernel/linux-5.4-lg115x.tgz`.

## Next

- Testers for each driver above.
- `5.4.96-115.16.mebbin.2` on K8Hp, which only one firmware file in the archive has.
- K6Lp's `4.4.84-612.35.jasper.2` (one firmware file, chip unknown).
- An `r8152` with RTL8156 support for 4.4 kernels, which needs Realtek's driver ported back.

## Testing one

If your TV runs one of the kernels above and you have a Realtek USB adapter, the TV app shows a **Test a new driver** row.  Or over SSH:

```sh
sh LG-USB-2-ETH0.sh test-driver
```

It finds the driver for your kernel (and chip), downloads it from [lg-webos-usb-drivers/experimental](https://github.com/ohmybahgosh/lg-webos-usb-drivers/tree/main/experimental) at a fixed commit, and keeps it only if its SHA-256 matches and it's built for exactly your kernel.  Then it loads it, in RAM and until the next restart only, moves your adapter to it, waits for it to get online and pings out through it.  It ends with a short report (no MAC or IP addresses) and a link to a [driver test report](https://github.com/ohmybahgosh/LG-USB-2-ETH0/issues/new?template=driver-test.yml); the app shows it as a QR code with the form filled in.  It marks the test as running before loading the driver, so if the TV freezes or restarts, the next `test-driver --last` (or opening the app) reports that too.  [Discussion #4](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/4) is for questions.  A driver that doesn't fit can at worst freeze or crash the TV until it restarts (unplug it if it doesn't on its own).  Nothing loads the driver again unless you do, so the TV comes back as it was.
