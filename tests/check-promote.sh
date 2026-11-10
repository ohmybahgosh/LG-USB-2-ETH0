#!/bin/sh
# Checks scripts/drivers.py promote on a copy of the repo: a "works" report
# moves exactly that row to TESTED_DRIVERS (and get-driver then offers it),
# anything else changes nothing.  Usage: tests/check-promote.sh SHA256SUMS
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUMS=$1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/assets"
cp "$ROOT/LG-USB-2-ETH0.sh" "$ROOT/README.md" "$T/"
cp "$ROOT/scripts/drivers.py" "$T/scripts/"
cp "$ROOT/assets/badge-drivers-to-test.svg" "$T/assets/"
# The first driver waiting for testers
row=$(sed -n 's/^EXPERIMENTAL_DRIVERS="//p' "$T/LG-USB-2-ETH0.sh")
# shellcheck disable=SC2086 # split the row into its fields on purpose
set -- $row
folder=$1
[ "$2" = - ] || folder=$1-$2
short=$(echo "$4" | cut -c1-16)
report() {
    # shellcheck disable=SC2016 # the backticks are Markdown, not a command
    printf '### The test report\n\n```text\nKernel:   %s\nDriver:   experimental/%s/%s (%s)\nResult:   %s\n```\n' "$1" "$folder" "$3" "$short" "$2" > "$T/report.txt"
}
fail() { echo "FAIL $1"; exit 1; }
before=$(sha256sum "$T/LG-USB-2-ETH0.sh")
report "$1" no-load "$3"
python3 "$T/scripts/drivers.py" promote "$T/report.txt" > /dev/null && fail "promoted a driver that didn't load"
[ "$(sha256sum "$T/LG-USB-2-ETH0.sh")" = "$before" ] || fail "changed the script for a failed test"
report "$1" works other.ko
python3 "$T/scripts/drivers.py" promote "$T/report.txt" > /dev/null && fail "promoted a file that isn't listed"
report "$1" works "$3"
python3 "$T/scripts/drivers.py" promote "$T/report.txt" || fail "didn't promote a working driver"
# The row is now in TESTED_DRIVERS (its first line, or a later one when
# others were promoted before) and no longer in EXPERIMENTAL_DRIVERS
awk -v r="$1 $2 $3 $4" '/^TESTED_DRIVERS="/ {t = 1} t {l = $0; sub(/^TESTED_DRIVERS="/, "", l); sub(/"$/, "", l); if (l == r) f = 1} t && /"$/ {t = 0} END {exit !f}' "$T/LG-USB-2-ETH0.sh" || fail "row not in TESTED_DRIVERS"
awk -v r="$1 $2 $3 $4" '/^EXPERIMENTAL_DRIVERS="/ {t = 1} t {l = $0; sub(/^EXPERIMENTAL_DRIVERS="/, "", l); sub(/"$/, "", l); if (l == r) f = 1} t && /"$/ {t = 0} END {exit f}' "$T/LG-USB-2-ETH0.sh" || fail "row still in EXPERIMENTAL_DRIVERS"
sh -n "$T/LG-USB-2-ETH0.sh" || fail "the script no longer parses"
python3 "$T/scripts/drivers.py" check --sums "$SUMS" || fail "check fails after promoting"
python3 "$T/scripts/drivers.py" promote "$T/report.txt" > /dev/null && fail "promoted the same driver twice"
# Realtek's driver doesn't use usbnet, so promoting it leaves a usbnet.ko
# for the same kernel among the drivers to test (it goes along with the
# ASIX and other drivers built on usbnet instead)
# Only rows still waiting for testers count: a kernel whose drivers were
# already promoted doesn't
awk '/^EXPERIMENTAL_DRIVERS="/ {t = 1} t {l = $0; sub(/^EXPERIMENTAL_DRIVERS="/, "", l); sub(/"$/, "", l); print l} t && /"$/ {t = 0}' "$T/LG-USB-2-ETH0.sh" > "$T/exp.txt"
u=$(sed -n 's/^\([0-9][^ ]*\) \([a-z0-9-]*\) usbnet\.ko \([0-9a-f]*\)$/\1 \2/p' "$T/exp.txt" | while read -r k c; do
    grep -q "^$k $c r8152_oot\.ko " "$T/exp.txt" && { echo "$k $c"; break; }
done)
if [ -n "$u" ]; then
    # shellcheck disable=SC2086 # split into kernel and chip on purpose
    set -- $u
    folder=$1
    [ "$2" = - ] || folder=$1-$2
    short=$(grep "^$1 $2 r8152_oot\.ko " "$T/exp.txt" | cut -d' ' -f4 | cut -c1-16)
    report "$1" works r8152_oot.ko
    python3 "$T/scripts/drivers.py" promote "$T/report.txt" > /dev/null || fail "didn't promote $folder/r8152_oot.ko"
    awk -v k="$1" -v c="$2" '/^EXPERIMENTAL_DRIVERS="/ {t = 1} t {l = $0; sub(/^EXPERIMENTAL_DRIVERS="/, "", l); if (l ~ "^" k " " c " usbnet\\.ko ") f = 1} t && /"$/ {t = 0} END {exit !f}' "$T/LG-USB-2-ETH0.sh" || fail "usbnet.ko went along with Realtek's driver"
fi
echo "promote: ok"
