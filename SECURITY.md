# Security policy

LG-USB-2-ETH0 runs as root on your TV and installs a boot hook, so security problems matter even for a small script.

## Supported versions

Only the [latest release](https://github.com/ohmybahgosh/LG-USB-2-ETH0/releases/latest) gets fixes.

## Reporting a problem

Please don't open a public issue for a security problem.  Report it privately through GitHub's [private vulnerability reporting](https://github.com/ohmybahgosh/LG-USB-2-ETH0/security/advisories/new) instead.

Include what you found, how to reproduce it, and which version you used.  You'll get a reply as soon as possible, and credit in the changelog if you'd like it.

## What the script does as root

So you can judge it yourself:

- Adds one boot hook, a link at `/var/lib/webosbrew/init.d/S01fix-eth` (or moves it to `/var/lib/webosbrew/S01fix-eth.disabled`), and keeps its settings in `/var/lib/webosbrew/lg-usb-2-eth0.conf` and its log in `/var/lib/webosbrew/lg-usb-2-eth0.log`.  Without the TV app, it keeps a copy of itself in `/home/root/lg-usb-2-eth0/`.
- Renames network interfaces with `ip link`, and brings them up and down.
- Writes its process ID and per-boot state to `/tmp` (RAM).
- Loads a kernel module with `insmod`, only if you install with `--module`, and only one built for your running kernel.  It then moves the USB adapter to that module's driver through `/sys/bus/usb/drivers` (unbind and bind), and turns off its scatter-gather setting.  After standby, if webOS doesn't reconnect the adapter on that driver, it takes the link down and up, or re-plugs the adapter in software (`/sys/bus/usb/devices/*/authorized`) so it goes back to the generic driver.
- `get-driver` downloads one file, only for a kernel listed in the script, from a fixed commit URL, and keeps it only if its SHA-256 matches.  Nothing else is downloaded.
- `update` downloads the newest release from GitHub, and installs it only if its SHA-256 matches (and its size, for the app).
- `speedtest` talks to Cloudflare's public speed test, only when you run it.
- With `--wifi-fallback`, it turns Wi-Fi on through webOS's connection manager when the cable has had no link for a minute, and off again when it works, remembering that in `/var/lib/webosbrew/lg-usb-2-eth0.wifi`.

Apart from `get-driver` and `update`, it doesn't download anything.  It never changes system files or opens any ports, and it changes network settings only if you turn on `--wifi-fallback`, which flips the Wi-Fi switch when the cable stops working and back when it works.

## Verifying a download

Every release has a `SHA256SUMS` file.  Download it next to the script and run:

```sh
sha256sum -c SHA256SUMS
```
