#!/bin/sh
# The checks are single-quoted on purpose: check() evals them.
# shellcheck disable=SC2016
# Checks scripts/firmware-audit/monitor.py against a small made-up firmware index.
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/index.json" <<'EOF'
{"fws": {
 "a/has-drivers.zip": {"lookupInfo": {"releaseDate": "2026-10-01", "modelNames": ["55UN7300PUF"]},
   "epks": [{"kernelVersion": "4.4.84-612.jcl4tv.40", "file": "starfish-secured-k6lp-jcl4tv-04.64.00_x.epk", "firmwareversion": "04.64.00.01"}]},
 "a/audited.zip": {"lookupInfo": {"releaseDate": "2026-10-02", "modelNames": ["65QNED99UPA"]},
   "epks": [{"kernelVersion": "4.4.84-229.kcl4tv.6", "file": "starfish-secured-e60n-koli-03.53.45_x.epk", "firmwareversion": "03.53.45.01"}]},
 "a/new.zip": {"lookupInfo": {"releaseDate": "2026-10-03", "modelNames": ["OLED65Z9PUA"]},
   "epks": [{"kernelVersion": "6.12.44-999.test.1", "file": "starfish-secured-z99-test-43.99.01_x.epk", "firmwareversion": "43.99.01.01"}]},
 "a/old.zip": {"lookupInfo": {"releaseDate": "2026-10-04", "modelNames": ["OLD"]},
   "epks": [{"kernelVersion": "3.10.19-1.old.1", "file": "starfish-secured-m14-old-05.00.00_x.epk", "firmwareversion": "05.00.00.01"}]},
 "a/too-early.zip": {"lookupInfo": {"releaseDate": "2025-01-01", "modelNames": ["EARLY"]},
   "epks": [{"kernelVersion": "5.4.96-998.test.1", "file": "starfish-secured-z98-test-03.00.00_x.epk", "firmwareversion": "03.00.00.01"}]}
}}
EOF
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
python3 scripts/firmware-audit/monitor.py new "$T/index.json" 2026-01-01 5 > "$T/new"
check "only the new kernel" '[ "$(wc -l < "$T/new")" = 1 ] && grep -q "6.12.44-999.test.1" "$T/new"'
check "with its chip" 'grep -q "\"chip\": \"z99\"" "$T/new"'
python3 scripts/firmware-audit/monitor.py coverage "$T/index.json" > "$T/cov"
check "coverage: drivers" 'grep -q "jcl4tv.40.*drivers to test or tested" "$T/cov"'
check "coverage: audited" 'grep -q "229.kcl4tv.6.*audited, no drivers yet" "$T/cov"'
check "coverage: skips kernel 3.x" '! grep -q "3.10.19" "$T/cov"'
cp "$T/new" "$T/pair.json"
printf 'z99\t43.99.01\tz99\ttest\t6.12.44-999.test.1\tr8152 asix ax88179_178a usbnet\tnone\tconfig\n' > "$T/audit"
python3 scripts/firmware-audit/monitor.py body "$T/pair.json" "$T/audit" > "$T/body"
check "body: works as is" 'grep -q "works on it as is" "$T/body"'
printf 'CONFIG_MODULES=y\nCONFIG_MODULE_SIG_FORCE=y\n' > "$T/config"
python3 scripts/firmware-audit/monitor.py body "$T/pair.json" "$T/audit" "$T/config" > "$T/body"
check "body: signing enforced" 'grep -q "Module signing is enforced" "$T/body"'
printf 'z99\t43.99.01\tz99\ttest\t6.12.44-999.test.1\tasix usbnet\tnone\tconfig\n' > "$T/audit"
python3 scripts/firmware-audit/monitor.py body "$T/pair.json" "$T/audit" > "$T/body"
check "body: drivers needed" 'grep -q "Missing: Realtek, ASIX AX88179" "$T/body"'
: > "$T/audit"
python3 scripts/firmware-audit/monitor.py body "$T/pair.json" "$T/audit" > "$T/body"
check "body: audit failed" 'grep -q "couldn.t read this firmware" "$T/body"'
exit $fail
