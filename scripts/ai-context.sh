#!/bin/sh
# Builds lg-usb-2-eth0-for-ai.md: one file with everything an AI assistant
# needs to work on this project (the guide, the commands, every function in
# the script with the comment above it, the TV app's parts, the tests and
# the latest changes).  Attach it to a chat assistant, or give it to a coding
# agent for a big change.  The release workflow attaches it to every release.
#
# Usage: sh scripts/ai-context.sh [OUTPUT]   (default: lg-usb-2-eth0-for-ai.md)

# shellcheck disable=SC2016 # backticks in single quotes are Markdown, not commands
set -e
cd "$(dirname "$0")/.."
OUT=${1:-lg-usb-2-eth0-for-ai.md}
SCRIPT=LG-USB-2-ETH0.sh
VER=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SCRIPT")

# functions FILE: "### name()" for each function, with the comment block
# right above it, grouped under the file's "# === Section ===" headings
functions() {
    awk '
        /^# === .* ===$/ { sub(/^# === /, ""); sub(/ ===$/, ""); printf "\n#### %s\n\n", $0; c = ""; next }
        /^CORE=\$\(cat <</ { print "\n*The functions from here to `CORE_EOF` are in `CORE`: the boot hook and detached jobs get them too.*"; c = ""; next }
        /^CORE_EOF$/ { print "\n*End of `CORE`.*"; c = ""; next }
        /^[[:space:]]*#/ { line = $0; sub(/^[[:space:]]*# ?/, "", line); c = c (c == "" ? "" : " ") line; next }
        /^[a-z_][a-z0-9_]*\(\) *\{/ {
            name = $0; sub(/\(\).*/, "", name)
            printf "- `%s()`", name
            if (c != "") printf ": %s", c
            printf "\n"
            c = ""; next
        }
        { c = "" }
    ' "$1"
}

# js_functions FILE: the same for the TV app
js_functions() {
    awk '
        /^[[:space:]]*\/\// { line = $0; sub(/^[[:space:]]*\/\/ ?/, "", line); c = c (c == "" ? "" : " ") line; next }
        /^[[:space:]]*function [A-Za-z0-9_]+\(/ {
            name = $0; sub(/^[[:space:]]*function /, "", name); sub(/\(.*/, "", name)
            printf "- `%s()`", name
            if (c != "") printf ": %s", c
            printf "\n"
            c = ""; next
        }
        /^[[:space:]]*[a-z]+: function/ {
            name = $0; sub(/^[[:space:]]*/, "", name); sub(/:.*/, "", name)
            printf "- action `%s`", name
            if (c != "") printf ": %s", c
            printf "\n"
            c = ""; next
        }
        { c = "" }
    ' "$1"
}

{
    echo "# LG-USB-2-ETH0 knowledge base for AI assistants"
    echo
    echo "Version $VER.  Built by \`scripts/ai-context.sh\` from the repository; don't edit it by hand."
    echo "Repository: https://github.com/ohmybahgosh/LG-USB-2-ETH0"
    echo
    sed '1d' docs/ai/GUIDE.md
    echo
    echo "## Commands and options"
    echo
    echo '```'
    NO_COLOR=1 sh "$SCRIPT" --help
    echo '```'
    echo
    echo "## Every function in the script"
    echo
    echo "From \`$SCRIPT\`, in order, with the comment above each one."
    functions "$SCRIPT"
    echo
    echo "## The TV app"
    echo
    echo "From \`webos-app/src/app.js\`.  The screen is \`webos-app/src/index.html\` and \`style.css\`; \`webos-app/build.sh\` builds the IPK."
    echo
    js_functions webos-app/src/app.js
    echo
    echo "## The app's languages"
    echo
    echo "From \`webos-app/src/i18n.js\`.  Each language is a dictionary keyed by the English text (\`T()\` and \`TC()\` in \`app.js\` look it up and fill in \`{placeholders}\`) and a list of patterns for the script's status messages (\`TS()\`).  \`tests/check-i18n.js\` checks every text in \`app.js\` and \`index.html\`, every status message and every \`toast_text()\` case.  Languages: $(sed -n "s/.*var NAMES = {\(.*\)};/\1/p" webos-app/src/i18n.js | sed "s/ *[a-z]*: '\([^']*\)'/\1/g; s/,/, /g; s/^ *//; s/ *$//")."
    echo
    js_functions webos-app/src/i18n.js
    echo
    echo "## Tests"
    echo
    echo "Each line is one test in \`tests/run.sh\` (run one with \`tests/run.sh busybox NAME\`):"
    echo
    sed -n 's/^t \([a-z0-9_]*\) .*/- `\1`/p' tests/run.sh
    echo
    echo "## Files"
    echo
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git ls-files | grep -v '^assets/\|\.png$\|\.svg$' | sed 's/^/- `/; s/$/`/'
    fi
    echo
    echo "## Latest changes"
    echo
    awk '/^## / { n++ } n >= 1 && n <= 3 { print }' CHANGELOG.md
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
