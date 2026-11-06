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
grep -q "^TESTED_DRIVERS=\"$1 $2 $3 $4\"$" "$T/LG-USB-2-ETH0.sh" || fail "row not in TESTED_DRIVERS"
sh -n "$T/LG-USB-2-ETH0.sh" || fail "the script no longer parses"
python3 "$T/scripts/drivers.py" check --sums "$SUMS" || fail "check fails after promoting"
python3 "$T/scripts/drivers.py" promote "$T/report.txt" > /dev/null && fail "promoted the same driver twice"
echo "promote: ok"
