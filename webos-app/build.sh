#!/bin/sh
# Build the LG-USB-2-ETH0 TV app (IPK) and its Homebrew Channel manifest.
#
# Usage: webos-app/build.sh [version]
#   version  like 2.3.0 (default: the script's VERSION with .0 added)
# Needs: ares-package (npm install -g @webos-tools/cli) and node.
# Output: webos-app/out/<id>_<version>_all.ipk and <id>.manifest.json
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SCRIPT="$ROOT/LG-USB-2-ETH0.sh"

SV=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SCRIPT")
case "$SV" in *.*.*) DEF=$SV ;; *) DEF="$SV.0" ;; esac
VERSION=${1:-$DEF}
case "$VERSION" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "Version must look like 2.3.0, got $VERSION" >&2; exit 1 ;; esac

DIST="$HERE/dist"
OUT="$HERE/out"
rm -rf "$DIST" "$OUT"
mkdir -p "$DIST/assets" "$OUT"
cp -R "$HERE/src/." "$DIST/"
cp "$SCRIPT" "$DIST/assets/lg-usb-2-eth0.sh"
chmod 755 "$DIST/assets/lg-usb-2-eth0.sh"
cp "$ROOT/LICENSE" "$DIST/LICENSE"

# QR code library (MIT, by Kazuhiko Arase), fetched from npm and checked
QR_VERSION=1.4.4
QR_SHA256=18ae399f81182bc9de916e9c77b195df20cc58d6f2d55a62b085a299f1bf1780
mkdir -p "$DIST/vendor" "$HERE/.cache"
QR_CACHE="$HERE/.cache/qrcode-$QR_VERSION.js"
if [ ! -f "$QR_CACHE" ]; then
    TMP=$(mktemp -d)
    (cd "$TMP" && npm pack --silent "qrcode-generator@$QR_VERSION" >/dev/null && tar xzf "qrcode-generator-$QR_VERSION.tgz")
    cp "$TMP/package/qrcode.js" "$QR_CACHE"
    rm -rf "$TMP"
fi
echo "$QR_SHA256  $QR_CACHE" | sha256sum -c - >/dev/null || { echo "qrcode.js checksum mismatch" >&2; rm -f "$QR_CACHE"; exit 1; }
cp "$QR_CACHE" "$DIST/vendor/qrcode.js"

node -e '
const fs = require("fs");
const f = process.argv[1];
const a = JSON.parse(fs.readFileSync(f, "utf8"));
a.version = process.argv[2];
fs.writeFileSync(f, JSON.stringify(a, null, 4) + "\n");
' "$DIST/appinfo.json" "$VERSION"

ares-package --no-minify "$DIST" -o "$OUT" >/dev/null
IPK=$(ls "$OUT"/*.ipk)
echo "Built $IPK"

node "$HERE/gen-manifest.js" "$DIST/appinfo.json" "$IPK" "$OUT"
