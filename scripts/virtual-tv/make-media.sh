#!/bin/sh
# Makes the README's TV app media on the virtual TV: the animation at the top
# of the TV app section (assets/app-tv.gif), the short clips and the
# screenshots (assets/screenshots).  Full-size PNGs and MP4s of everything,
# for web pages, go to $VTV_OUT (default webos-app/out/media).
# The update and v1 upgrade screenshots still come from scripts/screenshots/take.js.
#
#   sh webos-app/build.sh && sh scripts/virtual-tv/make-media.sh
#
# Needs Playwright, ffmpeg and a clone of lg-webos-usb-drivers next to this
# repository (see vtv.sh).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${VTV_OUT:-$REPO/webos-app/out/media}
SHOTS=$REPO/assets/screenshots
mkdir -p "$OUT" "$SHOTS"
cd "$OUT"
rec() { node "$HERE/record.js" "$@"; }

# 1600 pixels wide, 256 colours, to keep the repository small
png() {
    ffmpeg -v error -y -i "$1" -vf 'scale=1600:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a' "$SHOTS/$2"
    echo "wrote assets/screenshots/$2"
}

# The animation: a C9 in Realtek mode, the Wi-Fi backup and report boxes,
# back to the top so it loops
rec --scenario c9 --mp4 tour.mp4 --gif "$REPO/assets/app-tv.gif" \
    --steps 'wait:1300 down wait:1400 down*2 wait:400 ok wait:2800 back wait:700 down*4 wait:400 ok wait:3800 back wait:700 up*8 wait:1300'

# The clips
rec --scenario c2-new --mp4 clip-faster-driver.mp4 --gif "$SHOTS/clip-faster-driver.gif" --gif-width 800 \
    --steps 'wait:1300 down wait:1200 ok wait:3000 ok wait:6500 ok wait:3200'
rec --scenario c2-test --mp4 clip-test-driver.mp4 --gif "$SHOTS/clip-test-driver.gif" --gif-width 800 \
    --steps 'wait:3200 ok wait:3200 ok wait:10500 ok wait:3000'
rec --scenario c9 --mp4 clip-realtek-mode.mp4 --gif "$SHOTS/clip-realtek-mode.gif" --gif-width 800 \
    --steps 'wait:1300 down wait:1200 ok wait:2800 ok wait:3500 ok wait:1600 ok wait:3500 ok wait:2200'
rec --scenario c9-fresh --mp4 clip-switch-now.mp4 --gif "$SHOTS/clip-switch-now.gif" --gif-width 800 \
    --steps 'wait:2500 down*5 wait:900 ok wait:2600 ok wait:5000 ok wait:3200'

# The screenshots
rec --scenario c2 --steps 'wait:1500 down*6 wait:400 ok wait:12500 shot:app-speed.png back wait:900 down wait:300 ok wait:2500 shot:app-report.png back wait:1200 up*8 wait:900 shot:app-home.png'
rec --scenario c9 --steps 'wait:1500 down wait:800 shot:app-realtek.png'
rec --scenario c2-test --steps 'wait:2500 shot:app-drvtest-offer.png ok wait:2500 ok wait:10500 shot:app-drvtest-result.png'
for f in app-home app-speed app-report app-realtek app-drvtest-offer app-drvtest-result; do png "$f.png" "$f.png"; done
"$HERE/vtv.sh" stop
echo "Full-size PNGs and MP4s are in $OUT"
