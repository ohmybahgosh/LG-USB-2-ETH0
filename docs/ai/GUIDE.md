# LG-USB-2-ETH0 for AI assistants

This file is for people who work on LG-USB-2-ETH0 with an AI assistant (Claude, ChatGPT, Gemini, Copilot, Cursor and the like), and for the assistant itself.  Give your assistant the full knowledge base, not just this page:

- **Download:** <https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest/download/lg-usb-2-eth0-for-ai.md> (attached to every release), or run `sh scripts/ai-context.sh` in your clone to write `lg-usb-2-eth0-for-ai.md` from your own checkout.
- **Chat assistants** (claude.ai, ChatGPT, Gemini): attach the file at the start of the conversation, then describe what you want to change.
- **Coding agents** (Claude Code, Codex, Cursor, Copilot agent mode): they read `CLAUDE.md` or `AGENTS.md` in the repository by themselves, which point here.  For a big change, give them the full file too.

The project was built this way itself: v1 by hand, v2.0 on with AI coding agents, directed, reviewed and tested by the maintainer on a real TV.  Contributions made with AI are welcome on the same terms: say so in the pull request, understand every change, and test it on a real TV.

The rest of this page is written to the assistant.

---

## What LG-USB-2-ETH0 is

On rooted LG webOS TVs, a USB Ethernet adapter shows up as `eth1`, and parts of webOS only look at `eth0`, so settings say "Not Connected" and some apps refuse to play.  LG-USB-2-ETH0 renames the adapter to `eth0` and parks the built-in port (100 Mbit/s) under another name, at every boot.  It can also load a better driver module for Realtek adapters, keep the adapter on it, run a speed test, and update itself.

Four parts live in this repository:

1. **The script** (`LG-USB-2-ETH0.sh`): one POSIX `sh` file, run as root.  Commands: `install`, `uninstall`, `enable`, `disable`, `apply`, `revert`, `status` (`--json`), `report`, `get-driver`, `test-driver`, `speedtest`, `update`, and a menu with no command.  Install options include `--watch`, `--module`, `--wifi-fallback` and `--block-updates`.  Installing adds a boot hook for the Homebrew Channel: a symlink at `/var/lib/webosbrew/init.d/S01fix-eth` pointing at the script, with its settings in `/var/lib/webosbrew/lg-usb-2-eth0.conf`.
2. **The TV app** (`webos-app/`): a webOS web app (`org.ohmybahgosh.lgusb2eth0`) that bundles the script and runs it as root through the Homebrew Channel's exec service (`luna://org.webosbrew.hbchannel.service/exec`).  No service of its own.  `webos-app/build.sh` builds the IPK and its Homebrew Channel manifest.
3. **The tests** (`tests/`): `tests/run.sh` runs the script against a fake `/sys` with fake `ip`, `insmod`, `curl`, `luna-send`, `uname`, `nyx-cmd`, `iptables` and a fake sysfs writer (`tests/fakebin/`), under busybox `sh`, dash and bash.  `tests/check-issue-forms.py` checks the issue forms.
4. **Tools** (`scripts/`): `screenshots/` (the README screenshots and the real-TV recording), `banner/` (the README banner), `firmware-audit/` (unpacks LG firmware and lists its kernel's USB network drivers, results in `docs/firmware-audit.md`; with `SAVE=DIR` it keeps the kernel image and config), `driver-build/` (builds a driver module for one kernel from LG's source and checks its vermagic, exports and, on o22 5.4.268, struct offsets; see `docs/driver-build.md`), and `ai-context.sh` (this knowledge base).
5. **CI and releases** (`.github/workflows/`): `ci.yml` (ShellCheck, the tests on three shells, the issue forms, an app build), `release.yml` (on a `v*` tag: tests, builds the app, publishes the script, `SHA256SUMS`, the IPK, its manifest and this knowledge base), `notify-site.yml` (tells ohmybahgosh.dev to refresh its Homebrew Channel repository).

## Rules that are not optional

**It runs as root on someone's TV.**  A TV is expensive, and a boot hook runs again on every boot, including the bad ones.  Never write to the system partitions (signed squashfs; a failed write bricks the TV).  Never change webOS network settings: the script only renames interfaces and, with a driver module, moves an adapter between drivers.  The one exception is `--wifi-fallback`, which the user turns on: it flips webOS's own Wi-Fi switch (`wifi_set`) when `eth0` has had no cable link for a minute, only if Wi-Fi was off, and turns it off again (only if it turned it on, tracked in `WIFI_MARK`) once the cable works.  The other is `--block-updates`: it turns off webOS's update check (`softwareUpdateEnable`, old value kept in `UPD_MARK`), adds LG's update servers missing from `/etc/hosts` in lines tagged `UPD_TAG` (in a bind-mounted copy if `/etc/hosts` isn't writable, as the Homebrew Channel does), and one `iptables` rule for `UPD_IP`.  It never touches the Homebrew Channel's own block, and `updates_unblock` removes only what it added.  Every change needs a way back (renames are rolled back on failure, a driver that doesn't take the adapter gives it back), and a reboot without the hook must always start clean.

**POSIX `sh` under busybox.**  The TV's shell is busybox `sh`.  No bashisms: no `[[ ]]`, arrays, `local` (the tests may use it, the script doesn't), `$(< file)`, `echo -e`, `${var,,}`, process substitution or `function` keyword.  Use only common busybox applets (`sed`, `awk`, `tr`, `grep`, `sort`, `head`, `wc`, `readlink -f`, `sha256sum`).  ShellCheck runs as `shellcheck -s sh`, and CI uses ShellCheck 0.9.0, which flags `A && B || C` (SC2015): write an `if` instead.

**`CORE` is what the hook and detached jobs get.**  The functions between `CORE=$(cat <<'CORE_EOF'` and `CORE_EOF` are evaluated by the script and also passed to `run_detached`, which runs live changes (`apply`, `revert`) in their own session so they survive a dropped SSH connection.  A function a detached job calls must be inside `CORE`.  The heredoc is quoted, so no escaping is needed inside it.

**Check before acting, one try only.**  The hook does nothing without a settings file, or with invalid settings (`settings_ok`).  A driver module is loaded only if its file is there, it was built for the running kernel (`module_kernel` reads its `vermagic`) and its SHA-256 matches the one saved at install.  An adapter gets one takeover try per boot (`TAKEOVER_STATE`), so a driver that doesn't support it can't cause repeated drops.  Only adapters whose USB IDs the module lists are moved (`takeover_fits`), so a phone tethered over `cdc_ether` is never touched.

**Downloads are pinned and checked.**  `get-driver` downloads from a fixed commit and keeps the file only if its SHA-256 matches the one in `known_driver`.  Each entry also names a mirror in ohmybahgosh/lg-webos-usb-drivers (a fixed commit too), tried only when the author's copy fails.  A new driver goes in that repository as well.  `known_exact` lists drivers by exact kernel, `known_by_soc` by chip (`nyx-cmd DeviceInfo query device_name`) for builds whose vermagic is only the base version, and `pick_driver` chooses the one for the plugged-in adapter.  `module_fits` accepts a base-version vermagic only for a file whose SHA-256 is pinned for the running kernel.  `update` installs a release only after checking its SHA-256 (and size, for the app).  `fetch` uses HTTPS only, with time limits.  `test-driver` does the same for `experimental_driver`, the untested builds in the mirror's `experimental/` folder: pinned commit, SHA-256, and a vermagic that must be exactly the running kernel.  It loads one only by hand and only until the next restart (from `RUN_DIR`), never at boot, runs `drv_try` detached, and writes `DRVTEST_FILE` with `state=running` and the boot id first, so a test that froze the TV shows up as `result=crashed` after the restart.  Never add a download that isn't pinned and checked.

**The background check must stay cheap.**  `watch_run` wakes every few seconds for as long as the TV is on.  Its first checks are shell globs with no subprocesses; only when something changed does it look closer.  Keep it that way: no `$(...)`, pipes or external commands in the fast path.

**Wi-Fi, tethering and other USB devices are left alone.**  `is_usb_nic` skips Wi-Fi (even when it sits on USB), `rndis_host`, `ipheth`, `cdc_mbim` and `qmi_wwan`.  They're never renamed or moved.

**Performance tweaks need a measurement.**  On a C2 the USB 2.0 port is the limit, not the CPU (about a third busy at full speed), USB power saving is already off, and TCP buffers already grow to 6 MB.  Don't add sysctl, RPS or IRQ tweaks without numbers from a real TV showing they help.

**Settings survive.**  `install` keeps every setting not given on the command line (`SET_*` flags and `load_settings`).  An update replaces the script, never the settings file.

**Leave little behind.**  There's no uninstall hook on webOS.  The boot hook is a symlink, so it stops running when the app is removed.  What stays (the settings file, the log under `/var/lib/webosbrew/`, downloaded drivers in `/home/root/lg-usb-2-eth0/`) must stay small and clearly named.

**No secrets, no tracking.**  Never put real MAC addresses, IPs, logins or tokens in code, tests, fixtures or logs.  `report` masks MACs.  No telemetry.  The speed test talks to Cloudflare's public speed test only when the user asks for it.

**The TV app is plain ES5.**  Old webOS browsers run it: no `let`, `const`, arrow functions, template literals, classes, `async`, `?.`, `??`, `Array.from` or CSS grid.  It works with the remote alone (arrows, OK, Back) and with the Magic Remote pointer.  Back closes an overlay, then exits.

**Writing style for anything a person reads** (README, CHANGELOG, script output, app text, issue forms): plain words for TV owners, not developers; two spaces between sentences; never an em dash (use a colon, a comma or a new sentence).  Say what happens and what to do next.

## How a change is made

1. Read the parts you will touch.  Each function has a comment above it explaining what it does and why; keep it accurate.
2. Make the change in the right place (see "Where things go").
3. Add or update a test in `tests/run.sh`: a `test_name()` function using the fixtures (`add_builtin`, `add_usb`, `add_unclaimed`, `add_wifi`, `fake_ko`, `release`) and checks (`check "what" has "text"`, `lacks`, `rc_is`, `is`, `drv`, `json_ok`), plus a `t name test_name` line at the bottom.
4. Run the checks:

   ```sh
   tests/run.sh busybox          # closest to the TV; also dash and bash
   tests/run.sh busybox speed    # only tests whose name contains "speed"
   shellcheck -s sh LG-USB-2-ETH0.sh tests/fakebin/* && shellcheck tests/run.sh
   python3 tests/check-issue-forms.py
   node --check webos-app/src/app.js
   ```

5. Anything a user would notice: a line in `CHANGELOG.md` and the README (commands table, options table, the TV app section, troubleshooting).
6. If you can, try it on a real TV, and say which model and webOS version in the pull request.
7. Don't change `VERSION`, tag or publish releases, or edit `SHA256SUMS`.  The maintainer does that.

## Where things go

| You want to | Do it in |
|---|---|
| Add a command | `usage()`, the argument loop near the end (the `install\|uninstall\|...` line), the `case "$CMD"` dispatch, optionally the menu (`main_menu`), the README commands table, and a test |
| Add an install option | The defaults block, a `SET_*` flag, `settings_ok`, `load_settings`, `write_hook` (the settings file), `usage()`, the README options table |
| Change what happens at boot | `boot_main` (checks, then starts `boot_run` in the background), `boot_run`, and `watch_run` for after boot.  `boot_run` and `watch_run` are inside `CORE` |
| Add a known driver module | `known_driver`: `"url sha256 file page ids"`, pinned to a commit, with `ids` read from the module's own `alias=usb:v....p....` entries.  Add credit in the README (driver section and Thanks), a compatibility row, and a `driver_offer` test |
| Recognise another adapter chip | `known_nic_id` |
| Change `status` | `show_status` (people) and `show_json` (the app).  Keep both in step |
| Add something to the app | A button in `webos-app/src/index.html` (`data-action`), an entry in `actions` in `webos-app/src/app.js`, usually a script command with `--json`, and styles in `style.css` |
| Change the GitHub report | `show_report` (the text), the report action in `app.js` (the QR link), `.github/ISSUE_TEMPLATE/compatibility-report.yml` (field ids must match the link's parameters) |
| Change downloads | `fetch`, `get_driver`, `update_app`, `update_script`.  Keep them pinned and checked |
| Change what the app looks like | `webos-app/src/`, then the README screenshots: `scripts/screenshots/take.js` (and `demo.js` for new data) |
| Change the release | `.github/workflows/release.yml`, `webos-app/build.sh`, `webos-app/gen-manifest.js` |

## Testing without a TV

The test suite fakes the TV: `LGU2E_ROOT` moves every path under a temporary folder, `LGU2E_SYSFS` points at a fake `/sys`, and `LGU2E_SYSWRITE` routes writes to sysfs files (bind, unbind) through `tests/fakebin/syswrite`, which acts out what the kernel would do.  `LGU2E_SETTLE`, `LGU2E_WATCH_EVERY`, `LGU2E_SPEED_SECS`, `LGU2E_SPEED_URL` and `LGU2E_RELEASES` shorten waits and point downloads at the fake `curl`.  These are for tests only.

To preview the TV app in a desktop browser, open `webos-app/src/index.html` with a `window.LGU2E_DEMO = function (args, cb) { ... }` defined first.  It receives the script arguments and calls `cb(ok, stdout, stderr)` with made-up output.  `scripts/screenshots/demo.js` is a ready one, and `scripts/screenshots/take.js` uses it to take the README screenshots (`sh webos-app/build.sh && node scripts/screenshots/take.js`, with Playwright and ffmpeg).  If a change shows up on screen, take them again; keep the data made up.  The README's animation (`assets/app-tv.gif`) is recorded on a real TV with `scripts/screenshots/record-tv.js`, which only opens two read-only boxes and closes them.

## Things that look like bugs but are on purpose

- `SHA256SUMS` covers the script only, so `sha256sum -c SHA256SUMS` works on the TV with just the script downloaded.
- The report QR code opens `github.com/login?return_to=...`: the GitHub phone apps take over plain repository links and drop the form fields.
- "Options used" in the compatibility form is a text box: GitHub won't fill a multiple-choice dropdown from a link.  A dropdown option can't be called "None" either (GitHub reserves it and silently opens a blank issue instead); `tests/check-issue-forms.py` catches that.
- `status --json` picks `wlan*` for Wi-Fi, never `p2p*` (Wi-Fi Direct).
- After standby, `watch_run` waits up to 30 seconds before moving the adapter back to the faster driver (`takeover_after_standby`).  Moving it while webOS was still reconnecting left a C2 with no connection until a reboot.  After the move it checks that eth0 gets its address back, bounces the link if not, and as a last resort re-plugs the adapter in software (`authorized` 0 then 1) so it comes back on the generic driver.
- The app decides whether updates come from the Homebrew Channel by looking for `ohmybahgosh.dev/repo` in the Homebrew Channel's saved settings (`from_homebrew`).  If it's there, the app leaves updates to the Homebrew Channel.
- The script reports `VERSION` (for example `2.3.1`); the app's version comes from the release tag.

## Asking for a change

A prompt that works well, after attaching the knowledge base:

> I want LG-USB-2-ETH0 to *(the change)*.  On the TV, people should see *(what changes in `status`, the app or the log)*.  Follow the rules in the knowledge base: POSIX `sh` for busybox, nothing that can't be undone, pinned and checked downloads, a test in `tests/run.sh`, and the README and CHANGELOG.  First list the functions and files you'll change and why, then show the changes.

Ask your assistant to show you its plan before it writes code, and paste back the test output if anything fails.
