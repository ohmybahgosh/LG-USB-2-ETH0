# Wi-Fi wake in standby (`--wifi-wake`)

Turn the TV on over the network (Wake on LAN, **Turn on via Wi-Fi**, the LG ThinQ app, Home Assistant) while a USB adapter is its main connection.

- In the TV app: **Wi-Fi wake in standby**.
- Over SSH: `sh LG-USB-2-ETH0.sh install --wifi-wake`, and `--no-wifi-wake` to turn it off.

It starts right away, no restart needed, and again at every boot.  Tested on a 2022 C2 (webOS 25), woken from standby over Wi-Fi with the adapter back as the main connection afterwards, and on a G6 on webOS 26 ([discussion #19](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/19)).

## Contents

- [Why it's needed](#why-its-needed)
- [Set it up](#set-it-up)
- [Wake the TV](#wake-the-tv)
- [What it does](#what-it-does)
- [Check that it's working](#check-that-its-working)
- [What the log lines mean](#what-the-log-lines-mean)
- [Troubleshooting](#troubleshooting)
- [Turning it off](#turning-it-off)
- [For developers](#for-developers)

## Why it's needed

LG's network wake listens on Wi-Fi, and on the built-in port when it has a cable.  It never listens on a USB adapter: standby resets the TV's USB ports, so the adapter is gone by the time a wake-up packet arrives.  That leaves Wi-Fi as the way to wake a TV that uses an adapter.

Two things get in the way of that:

- **Some TVs drop off Wi-Fi in standby while the adapter is the main connection.**  An LG G6 on webOS 26 did this ([discussion #19](https://github.com/ohmybahgosh/LG-USB-2-ETH0/discussions/19)): Wi-Fi was connected while the TV was on, but couldn't be woken once it was off.
- **Some TVs turn Wi-Fi off when a cable is connected.**  A C2 on webOS 25 turned Wi-Fi off at boot with the adapter connected, and didn't join Wi-Fi again on its own once it was turned back on.

And once Wi-Fi is kept connected next to the adapter, webOS's connection manager (ConnMan) can move the TV's traffic over to Wi-Fi.  It ranks a connection it has checked as online ahead of one that's only ready, so when Wi-Fi reconnects and passes its check, the internet goes through Wi-Fi instead of the adapter.  On the C2 that meant apps slowed down or stopped loading until Wi-Fi was turned off.

`--wifi-wake` handles all three: it keeps Wi-Fi on and joined, keeps the adapter first for traffic, and hands over to Wi-Fi just before standby.

## Set it up

1. **Install the boot hook** (the TV app's **Run at every boot**, or `install` over SSH).  `--wifi-wake` is a setting of the boot hook.
2. **Turn on the TV's Turn on via Wi-Fi.**  It's in the TV's settings, usually under **General > Devices > External Devices > TV On With Mobile** (the names move around a little between years).  Without it, `--wifi-wake` does nothing: the TV isn't listening for a wake-up anyway.
3. **Join your Wi-Fi network once** in the TV's network settings, so the TV has it saved.  It's fine to leave it joined.  If webOS turns Wi-Fi off later, `--wifi-wake` turns it back on and joins that same saved network.
4. **Give Wi-Fi its own IP address.**  If you set a fixed IP on the TV, don't use the adapter's IP for Wi-Fi too.  Two connections with the same address break the TV's connection: traffic goes out either way at random.  `--wifi-wake` disconnects Wi-Fi if it finds this, and `status` warns about it.  Letting your router hand out addresses (DHCP), with a reservation for each MAC, is easiest.
5. **Turn on Wi-Fi wake in standby** in the app, or run:

   ```sh
   sh LG-USB-2-ETH0.sh install --wifi-wake
   ```

   The app says "Wi-Fi wake in standby is on now, no restart needed."

## Wake the TV

Send the wake-up (a "magic packet") to the **Wi-Fi MAC address**, not the adapter's.  `status` prints the one to use:

```
Turning the TV on over the network (Turn on via Wi-Fi, apps, Home Assistant) goes through Wi-Fi, not the adapter: standby resets the USB ports.  Wake it by wlan0's MAC, aa:bb:cc:dd:ee:ff.
```

If the built-in port has a cable in it, `status` names that port's MAC instead, since the TV wakes on it too.

Send it to your network's broadcast address (like `192.168.1.255` on a `192.168.1.x` network, or `255.255.255.255`), on port 9.

- **A phone app** (any Wake on LAN app): MAC = the Wi-Fi MAC, broadcast address as above, port 9.
- **Linux or a Pi**: `wakeonlan -i 192.168.1.255 aa:bb:cc:dd:ee:ff`, or `etherwake -i <interface> aa:bb:cc:dd:ee:ff`.
- **Home Assistant**: `wake_on_lan.send_magic_packet` with `mac: aa:bb:cc:dd:ee:ff` and `broadcast_address: 192.168.1.255`, for example in the LG webOS integration's **Turn on** automation.
- **The LG ThinQ app** uses Turn on via Wi-Fi on its own, as long as the TV is still known to it.

If an app or Home Assistant learned the TV's "wired" MAC after the switch, that's the adapter's.  Point it at the Wi-Fi MAC instead.

**A wake can be a full boot.**  From light standby the TV resumes in a few seconds.  After a longer time off, a TV can be in deeper standby, and waking it boots it fresh: the log shows a boot instead of a resume.  Both are normal, and `--wifi-wake` connects the adapter again either way.

## What it does

It follows the TV's power state through webOS's own power service (`com.webos.service.tvpower`), in a small background process (the standby follower).

**When it starts** (when you turn it on, and at every boot):

1. If webOS left Wi-Fi off, it turns Wi-Fi on.
2. If Wi-Fi isn't joined, it joins the network the TV already has saved (set to connect automatically).
3. If Wi-Fi ended up with the adapter's IP address, it disconnects Wi-Fi and logs why.
4. It puts the adapter ahead of Wi-Fi, so traffic goes over the cable.
5. It starts a check that runs every 10 seconds: if the TV's internet (the default route) has moved to Wi-Fi, it puts the adapter first again.  That's one `ip route` each time and nothing else unless Wi-Fi has taken over.

**Just before standby** (as soon as webOS says the TV is going down, like "Request Active Standby" or "Prepare Power Off"), it hands over to Wi-Fi, only when all of this is true:

- `eth0` is the USB adapter, and it's connected.
- Wi-Fi is connected.
- Turn on via Wi-Fi is on in the TV's settings.
- webOS's connection manager has exactly one connection for the adapter and one for Wi-Fi.

Then it disconnects **only the adapter's network session** in the connection manager.  The adapter stays plugged in, keeps its driver and stays `eth0`.  It also keeps Wi-Fi's wake turned on, and writes down what it disconnected in `/var/lib/webosbrew/lg-usb-2-eth0.wake`.

If any of that isn't true, it leaves the adapter connected and logs why.

**When the TV is on again** (the power state is Active, Screen Saver or Screen Off), or at the next boot if the TV lost power in standby, it connects the adapter again:

1. It waits for the adapter to come back as `eth0` with a cable link.  After standby that can take a few seconds.
2. It connects the adapter's session and waits up to 10 seconds for an address.
3. It puts the adapter ahead of Wi-Fi again, and makes sure Wi-Fi is still on and joined for the next standby.

It tries up to 10 times, 3 seconds apart, and logs why each try didn't work.  If all 10 fail, it tries again at the next wake.

**What it doesn't do:** it never renames or moves the Wi-Fi interface, never changes your Wi-Fi network or password, and never touches the adapter's driver.  The only lasting change is that Wi-Fi is turned on when webOS had it off.

**A TV turning on isn't a TV going to sleep.**  A C2 reports the state "Active Standby" with "Screen On" in progress while it's waking up.  `--wifi-wake` only hands over on Active Standby when nothing else is in progress, so it doesn't disconnect the adapter while the TV turns on (fixed in 2.11.9).

## Check that it's working

**In the TV app**, the status screen shows **Wi-Fi wake in standby** turned on, and any problem it finds.

**Over SSH**:

```sh
# Is the follower running?  Three processes: the follower, its keep-first check, and luna-send
for f in /tmp/lg-usb-2-eth0/lg-usb-2-eth0.wake.pid*; do echo "$f: $(cat $f)"; done

# Is the internet going through the adapter?
ip route | head -1          # default via ... dev eth0
connmanctl services | head -2
# *AO Wired                 the adapter, online
# *AR YourNetwork           Wi-Fi, ready behind it

# What has it done?
grep -E "power:|standby:|awake:|Wi-Fi" /var/lib/webosbrew/lg-usb-2-eth0.log | tail -20
```

A full standby and wake looks like this in the log (from a C2):

```
=== power: Active Standby ===
=== standby: disconnected the adapter's network session, so Wi-Fi stays ready for wake ===
=== power: Active Standby (Request Suspend) ===
=== power: Active Standby (Prepare Power Off) ===
=== power: Power Off ===
=== boot hook (wait 120s, module /home/root/lg-usb-2-eth0/drivers/r8152_oot.ko) ===
Done: the USB adapter is eth0, the built-in port is eth2.
=== awake: try 1 of 10: the adapter has no cable link yet ===
=== awake: the adapter is connected again (try 2) ===
Following standby for Wi-Fi wake.
=== power: Active ===
```

## What the log lines mean

Every line in the log starts with the date.  These are the ones from `--wifi-wake`.

| Log line | What it means |
| --- | --- |
| `Following standby for Wi-Fi wake.` | The follower started. |
| `power: STATE (PROCESSING)` | A change in the TV's power state, as webOS reported it.  Useful to see what your TV sends. |
| `standby: disconnected the adapter's network session, so Wi-Fi stays ready for wake` | It handed over to Wi-Fi.  This is what should happen before standby. |
| `standby: Wi-Fi isn't connected, so the adapter stays connected` | Join Wi-Fi in the TV's settings. |
| `standby: network wake is off in the TV's settings, so the adapter stays connected` | Turn on **Turn on via Wi-Fi**. |
| `standby: eth0 isn't a connected USB adapter, so nothing to hand over` | The adapter isn't `eth0`, or has no address. |
| `standby: no single connection for the adapter` / `no single Wi-Fi connection` | The connection manager listed none, or more than one.  Please open an issue with `connmanctl services`. |
| `standby: couldn't disconnect the adapter, so it stays connected` | The connection manager refused.  Please open an issue. |
| `awake: the adapter is connected again (try N)` | It's back, and first. |
| `awake: try N of 10: REASON` | A try that didn't work yet, and why: no `eth0` yet, `eth0` isn't the adapter yet, no cable link yet, or no address after 10 seconds. |
| `awake: couldn't connect the adapter again after 10 tries` | It'll try again at the next wake.  Turning the TV off and on gives it another 10 tries, or see [Troubleshooting](#troubleshooting) to connect it by hand. |
| `Wi-Fi for wake: turned Wi-Fi on` | webOS had Wi-Fi off, so it turned it on. |
| `Wi-Fi for wake: joined the saved network, with the adapter still first` | Wi-Fi joined, and the adapter stays the main connection. |
| `Wi-Fi for wake: no saved network to join, so join one in the TV's settings` | The TV has no Wi-Fi network saved. |
| `Wi-Fi for wake: Wi-Fi has the adapter's address too (IP)...` | Both have the same IP.  Give Wi-Fi its own in the TV's network settings. |
| `Wi-Fi had taken over the connection, so the adapter is first again` | The connection manager moved traffic to Wi-Fi, and it was moved back. |

## Troubleshooting

**The internet stops working, or gets slow, with Wi-Fi on.**  Update to 2.11.8 or newer: it keeps the adapter ahead of Wi-Fi.  Check `ip route | head -1` says `dev eth0`.  If Wi-Fi and the adapter have the same IP, give Wi-Fi its own (see [Set it up](#set-it-up)).

**The TV doesn't wake.**

- Send the wake-up to the **Wi-Fi** MAC that `status` prints, not the adapter's.
- Check **Turn on via Wi-Fi** is on in the TV's settings.
- Look for a `standby:` line in the log from when you turned the TV off.  If it says the adapter stays connected, it says why.
- Send it to your network's broadcast address on port 9.  Some phone apps default to a different port or the TV's last IP, which doesn't answer in standby.
- If the TV was unplugged or lost power, it can't be woken until it's been turned on once.

**The adapter disconnects and reconnects a couple of seconds after the TV turns on.**  Update to 2.11.9 or newer.

**The adapter doesn't come back after a wake.**  Look for `awake: try` lines.  "No cable link yet" on every try means the adapter isn't getting a link back after standby; try another USB port or a powered hub.  Turning the TV off and on again gives it another 10 tries.  To connect it by hand over SSH, find the `Wired` line in `connmanctl services` and run `connmanctl connect` with the ID at the end of that line.

## Turning it off

Turn off **Wi-Fi wake in standby** in the app, or run:

```sh
sh LG-USB-2-ETH0.sh install --no-wifi-wake
```

That stops the follower right away.  **Turn everything off** (`uninstall`) stops it too.  Wi-Fi stays on if `--wifi-wake` turned it on; turn it off in the TV's network settings if you don't want it.

## For developers

- The follower is started detached (`setsid`), and its PIDs are kept in `/tmp/lg-usb-2-eth0/lg-usb-2-eth0.wake.pid`, `.wake.pid.keep` and `.wake.pid.luna`.
- Power states come from `luna-send -i luna://com.webos.service.tvpower/power/getPowerState '{"subscribe":true}'`.  If that ends, it subscribes again 10 seconds later.
- The Turn on via Wi-Fi setting is read from ConnMan's `WOLWOWLMode` over the system bus with `busctl`, or webOS's `wolwowlOnOff` setting when `busctl` can't tell.  On a C2 the bus socket is at `/var/run/dbus/system_bus_socket`, which `busctl` doesn't look at on its own.
- Handing over is `connmanctl disconnect` on the adapter's service.  Coming back is `connmanctl connect` and `connmanctl move-before` with the Wi-Fi service.
- Environment variables, mostly for the tests: `LGU2E_WAKE_TRIES` (10), `LGU2E_WAKE_RETRY_SECS` (3), `LGU2E_WAKE_ADDR_SECS` (10), `LGU2E_WAKE_KEEP_SECS` (10).
- The tests (`tests/run.sh`, the `wifi_wake` tests) run it against fake `luna-send`, `connmanctl` and `busctl`, including a C2's power states and a power cut in standby.
