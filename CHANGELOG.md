# Changelog

All notable changes to LG-USB-2-ETH0.  Versions follow [semantic versioning](https://semver.org/).

## [2.1.0] - 2026-11-01

### Added

- `--watch`: the boot hook keeps following the adapter after boot.  Plug it in and it becomes `eth0`.  Unplug it and `eth0` goes back to the built-in port, so the TV is never left without an `eth0`.
- `report`: a short, paste-ready block for GitHub issues, with MAC addresses masked.  Also in the menu.
- `status` shows whether `--watch` is on and whether the hook's background job is running.
- More known USB Ethernet chip IDs (Apple, Samsung, NVIDIA, Lenovo and more ASIX), so `status` spots more adapters that have no driver.
- A test suite (`tests/run.sh`) that runs the script against a fake `/sys` and a fake `ip` under busybox `sh`, dash and bash.
- CI: ShellCheck and the test suite on every push and pull request.
- Releases with a `SHA256SUMS` file, published from tags.
- Issue templates for compatibility reports and bugs, and a security policy.

### Changed

- Renames are retried up to 3 times.  webOS can bring an interface back up between `down` and the rename, which made it fail with "Device or resource busy".
- `install`, `uninstall` and `disable` stop the hook's background job first.
- `apply` and `revert` say when the switch is still running after 20 seconds, instead of printing a partial log.
- Wi-Fi shows as "connected" in `status` rather than "cable in".
- No colors when the output isn't a terminal, or when `NO_COLOR` is set, so logs and pasted output stay clean.
- The hook appends the system directories to `PATH` instead of putting them first.
- README rewritten: safety and undo up front, table of contents, adapter guide, sourced speed table, FAQ, development guide.

### Security

- `--module` only accepts plain path characters (letters, digits, `.`, `_`, `-` and `/`).  The path is written into a root boot script, so a crafted path could otherwise have run commands at every boot.

## [2.0] - 2026-10-26

### Changed

- The built-in port is only renamed when an adapter is actually there.  v1 renamed `eth0` to `eth2` at every boot even with no adapter plugged in, which left the TV with no `eth0`.
- The boot hook waits for the adapter in the background (120 s by default) and never holds up the Homebrew Channel startup.
- The adapter is found automatically and checked to really be USB Ethernet, so `eth1`, `eth2` and `usb0` all work and the Wi-Fi module is never grabbed.
- A failed rename puts the old names back.
- `apply` and `revert` run detached, so they finish when the SSH session drops, and warn first if you're connected through a port that's about to change.
- A disabled hook is moved out of `init.d`.  v1 renamed it to `S01fix-eth.disabled` inside `init.d`, where busybox `run-parts` still ran it.

### Added

- `status` / `doctor`.
- `--mac`, `--wait`, `--module` and `-y`.

## [1.0]

- First release: renames `eth0` to `eth2` and `eth1` to `eth0` at every boot.

[2.1.0]: https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/tag/v2.1.0
