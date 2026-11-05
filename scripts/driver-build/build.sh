#!/bin/sh
# Build a USB Ethernet driver module for one LG TV kernel, then check it.
#
# Usage: scripts/driver-build/build.sh KERNEL_DIR SOURCE_TREE DRIVER [OUT]
#
#   KERNEL_DIR   a folder with that kernel's config and Image, as
#                scripts/firmware-audit/audit.sh saves them with SAVE=DIR
#                (the folder name labels the output, like 5.4.268-329.ptl4tv.2,
#                or the chip when one kernel name has a config per chip).
#                Without firmware to take them from, it can instead hold the
#                config and the Module.symvers of a full build of LG's
#                source, plus a file named release with the kernel name.
#   SOURCE_TREE  LG's kernel source for that platform (linux-rockhopper from
#                the TV's package on opensource.lge.com)
#   DRIVER       r8152: Realtek's r8152 v2.22.1 as DonZoomik/webos-r8152
#                patched it, built as r8152_oot so it can sit next to the
#                built-in driver (5.x kernels).
#                intree:NAME: drivers/net/usb/NAME.c from LG's own source,
#                like intree:ax88179_178a or intree:r8152, for kernels that
#                leave it out
#   OUT          where to put the module and its report (default: ./out)
#
# Needs aarch64-linux-gnu- and arm-linux-gnueabihf- cross compilers (set
# CROSS_COMPILE and CROSS_COMPILE_COMPAT to override), and for r8152,
# DRIVER_SRC set to a checkout of DonZoomik/webos-r8152.  Both 64-bit
# (arm64) and 32-bit (ARMv7) kernels work.  On 4.x kernels the build goes
# through cc-no-werror, since a new GCC warns where LG's -Werror code
# didn't use to, with HOSTCFLAGS=-fcommon for their host tools.  Realtek-chip sources also need
# CHIP_NAME (like k24) and LG's drivers/rtk_kdriver tree, or empty
# drivers/rtk_kdriver/common_header/CHIP/include and .../rbus/CHIP folders in
# its place (r8152 doesn't use anything from it).  If the TV's config has
# options the source doesn't define and a kernel header uses one, the build
# stops: kconfig-stub.py writes declarations for them.  It never touches a TV.
#
# The module is kept only if its vermagic is exactly the kernel's, the kernel
# has MODVERSIONS off, and every symbol it imports is exported by the kernel
# image.  On o22-family 5.4.268 kernels the USB struct offsets the driver
# relies on are checked too (tv_abi_checks.h, a compile error otherwise).
# Elsewhere the report says "struct offsets unchecked" and the module needs
# a tester.
set -eu

KDIR=$1
SRC=$2
DRIVER=$3
OUT=${4:-$PWD/out}
HERE=$(cd "$(dirname "$0")" && pwd)
LABEL=$(basename "$KDIR")
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
CROSS_COMPILE_COMPAT=${CROSS_COMPILE_COMPAT:-arm-linux-gnueabihf-}

[ -f "$KDIR/config" ] || { echo "$KDIR has no config" >&2; exit 1; }
[ -f "$SRC/Makefile" ] || { echo "no kernel source at $SRC" >&2; exit 1; }
# The kernel's own name, from the image (the folder name is just a label,
# since one kernel name can be built for several chips with different configs)
if [ -f "$KDIR/Image" ]; then
    KERNEL=$(python3 -c 'import re,sys; m=re.search(rb"Linux version (\S+) \(", open(sys.argv[1],"rb").read()); print(m.group(1).decode() if m else "")' "$KDIR/Image")
    EXPORTS=$KDIR/Image
elif [ -f "$KDIR/Module.symvers" ] && [ -f "$KDIR/release" ]; then
    KERNEL=$(head -n 1 "$KDIR/release")
    EXPORTS=$KDIR/Module.symvers
else
    echo "$KDIR needs Image, or Module.symvers and release" >&2; exit 1
fi
[ -n "$KERNEL" ] || { echo "no kernel name for $KDIR" >&2; exit 1; }
grep -q '^# CONFIG_MODVERSIONS is not set' "$KDIR/config" || {
    echo "$KERNEL has MODVERSIONS on: a module needs its symbol CRCs, not supported here" >&2; exit 1; }
if grep -q '^CONFIG_ARM64=y' "$KDIR/config"; then
    ARCH=arm64
elif grep -q '^CONFIG_ARM=y' "$KDIR/config"; then
    # 32-bit: one compiler, and the kernel's old Makefiles need the CPU
    # spelled out for a new assembler
    ARCH=arm
    CROSS_COMPILE=${CROSS_COMPILE_ARM:-arm-linux-gnueabihf-}
    ARCH_CFLAGS="-march=armv7-a"
else
    echo "$KERNEL is neither arm64 nor arm" >&2; exit 1
fi

# The release is VERSION.PATCHLEVEL.SUBLEVEL from the source, then a suffix
BASE=$(sed -n 's/^VERSION = //p; s/^PATCHLEVEL = //p; s/^SUBLEVEL = //p' "$SRC/Makefile" | head -n 3 | tr '\n' '.' | sed 's/\.$//')
case "$KERNEL" in
    "$BASE"*) LOCALVERSION=${KERNEL#"$BASE"} ;;
    *) echo "source is $BASE, kernel is $KERNEL" >&2; exit 1 ;;
esac

case "$DRIVER" in
    intree:*)
        NAME=${DRIVER#intree:}
        [ -f "$SRC/drivers/net/usb/$NAME.c" ] || { echo "no drivers/net/usb/$NAME.c in $SRC" >&2; exit 1; }
        FILES="$SRC/drivers/net/usb/$NAME.c"
        MODULE=$NAME.ko
        DRIVER=$NAME
        ;;
    r8152)
        : "${DRIVER_SRC:?set DRIVER_SRC to a checkout of DonZoomik/webos-r8152}"
        D=$DRIVER_SRC/realtek-r8152-v2.22.1
        FILES="$D/r8152.c $D/compatibility.h $D/Makefile $DRIVER_SRC/outputs/tv_abi_checks.h"
        MODULE=r8152_oot.ko
        ;;
    *) echo "unknown driver $DRIVER" >&2; exit 1 ;;
esac

WORK=$OUT/$LABEL/$DRIVER
B=$WORK/kbuild
M=$WORK/$DRIVER
rm -rf "$B" "$M"
mkdir -p "$B" "$M"
cp "$KDIR/config" "$B/.config"
# shellcheck disable=SC2086
cp $FILES "$M/"
[ -f "$M/Makefile" ] || echo "obj-m := ${MODULE%.ko}.o" > "$M/Makefile"

# LG's Makefiles only use the source tree's own path for their include
# folders when this is set (DonZoomik's build does the same)
export PKG_CONFIG_SYSROOT_DIR=/
set -- -C "$SRC" O="$B" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" LOCALVERSION="$LOCALVERSION"
if [ "$ARCH" = arm64 ]; then
    # The 32-bit compat vDSO is built during kernel prep, and needs ARMv8
    # instructions the compat compiler doesn't use by default.  It isn't
    # part of the module.
    _cc32=$WORK/compat
    mkdir -p "$_cc32"
    for _t in as ld objcopy objdump nm strip ar readelf; do
        _p=$(command -v "${CROSS_COMPILE_COMPAT}$_t") && ln -sf "$_p" "$_cc32/${CROSS_COMPILE_COMPAT##*/}$_t"
    done
    printf '#!/bin/sh\nexec %s "$@" -march=armv8-a\n' "$(command -v "${CROSS_COMPILE_COMPAT}gcc")" > "$_cc32/${CROSS_COMPILE_COMPAT##*/}gcc"
    chmod +x "$_cc32/${CROSS_COMPILE_COMPAT##*/}gcc"
    set -- "$@" CROSS_COMPILE_COMPAT="$_cc32/${CROSS_COMPILE_COMPAT##*/}"
fi
case "$BASE" in
    4.*)
        export REAL_CC="${CROSS_COMPILE}gcc"
        set -- "$@" CC="$HERE/cc-no-werror" HOSTCFLAGS=-fcommon ;;
esac
LOG=$WORK/build.log
make "$@" olddefconfig > "$LOG" 2>&1
python3 "$SRC/scripts/diffconfig" "$KDIR/config" "$B/.config" > "$WORK/config-differences.txt" || true
# Options in the TV's config that this source doesn't know are dropped.
# That's harmless unless a kernel header uses one the TV turns on (Realtek's
# options in page-flags.h or thread_info.h, for example): then a module would
# get a different struct layout than the TV's kernel.  Stop if so.  One the
# TV has off is the same as one that doesn't exist.
_lost=$(sed -n 's/^-\([A-Za-z0-9_]*\) [^n].*/\1/p' "$WORK/config-differences.txt" | while read -r _o; do
    if grep -rqw "CONFIG_$_o" "$SRC/include" "$SRC/arch/$ARCH/include" 2>/dev/null; then printf ' %s' "$_o"; fi
done)
if [ -n "$_lost" ]; then
    echo "The TV's config has options this source doesn't define, and kernel headers use them:$_lost" >&2
    echo "Give the source their Kconfig (kconfig-stub.py makes one from the TV's config) and build again." >&2
    exit 1
fi
make "$@" -j"$(nproc)" modules_prepare >> "$LOG" 2>&1
grep -Fqx "#define UTS_RELEASE \"$KERNEL\"" "$B/include/generated/utsrelease.h" || {
    echo "built release doesn't match $KERNEL" >&2; exit 1; }
# tv_abi_checks.h pins USB struct offsets measured on a real TV with LG's
# own chip (o22) and a 5.4.268 kernel (DonZoomik's crash dump).  The layout
# depends on the config (struct device grows with PINCTRL and others), so on
# other chips and kernels the module is built without it and reported as
# unchecked: it then needs someone with that TV to try it.
ABI=unchecked KCFLAGS=${ARCH_CFLAGS:-}
case "$KERNEL" in
    5.4.268-*)
        if [ "$DRIVER" = r8152 ] && grep -q '^CONFIG_ARCH_LG1K=y' "$KDIR/config"; then
            ABI=checked KCFLAGS="-include $M/tv_abi_checks.h"
        fi ;;
esac
make "$@" M="$M" ${KCFLAGS:+"KCFLAGS=$KCFLAGS"} modules >> "$LOG" 2>&1 || {
    echo "build failed (struct offsets differ, or a compile error): $LOG" >&2; exit 1; }

KO=$M/$MODULE
"${CROSS_COMPILE}readelf" -p .modinfo "$KO" > "$WORK/modinfo.txt"
grep -Fq "vermagic=$KERNEL " "$WORK/modinfo.txt" || { echo "vermagic doesn't match" >&2; exit 1; }
"${CROSS_COMPILE}nm" -u "$KO" | awk '{print $NF}' > "$WORK/imports.txt"
python3 "$HERE/check-exports.py" "$EXPORTS" "$WORK/imports.txt" > "$WORK/exports.txt" || {
    cat "$WORK/exports.txt" >&2; exit 1; }
cp "$KO" "$WORK/$MODULE"
rm -rf "$B"
SHA=$(sha256sum "$WORK/$MODULE" | cut -d' ' -f1)
printf '%s\t%s\t%s\t%s\t%s\t%s\tstruct offsets %s\n' "$LABEL" "$KERNEL" "$DRIVER" "$MODULE" "$SHA" "$(cat "$WORK/exports.txt")" "$ABI"
