/*
 * LG-USB-2-ETH0 TV app.
 *
 * A remote-friendly front end for the LG-USB-2-ETH0 script bundled with the
 * app. Root commands go through the Homebrew Channel's own root service
 * (luna://org.webosbrew.hbchannel.service/exec), so the app needs no service
 * of its own. Written as plain ES5 so it runs on older webOS browsers too.
 */
(function () {
    'use strict';

    // The app's words in the TV's language (i18n.js); English if it's missing
    var I18N = window.LGU2E_I18N || null;
    var T = I18N ? I18N.T : function (t, v) { return v ? t.replace(/\{(\w+)\}/g, function (m, k) { return k in v ? v[k] : m; }) : t; };
    var TS = I18N ? I18N.TS : function (t) { return t; };

    var REPO_PATH = '/ohmybahgosh/LG-USB-2-ETH0';
    var REPO = 'https://github.com' + REPO_PATH;

    // Query-string encoding that keeps the URL short: spaces become + and the
    // characters that are safe in a query value stay as they are
    function q(v) {
        return encodeURIComponent(v).replace(/%20/g, '+').replace(/%3A/g, ':').replace(/%2C/g, ',').replace(/%2F/g, '/');
    }
    var HBC_EXEC = 'luna://org.webosbrew.hbchannel.service/exec';
    var KEY = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13, BACK: 461, ESC: 27, BACKSPACE: 8 };

    // The script ships inside the app: <app dir>/assets/lg-usb-2-eth0.sh
    var appDir = decodeURIComponent(window.location.pathname).replace(/\/[^\/]*$/, '');
    var SCRIPT = appDir + '/assets/lg-usb-2-eth0.sh';

    var state = null;      // last status --json result
    var busy = false;
    var upd = null;        // last update --check --json result
    var overlayMode = null; // null, 'busy', 'message', 'confirm', 'pick'
    var onConfirm = null;

    function $(id) { return document.getElementById(id); }

    function esc(s) {
        return String(s === undefined || s === null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // Single-quote a string for the shell
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    // ------------------------------------------------------------------ luna

    var bridges = [];
    function luna(uri, params, cb) {
        if (typeof window.PalmServiceBridge === 'undefined') {
            cb({ returnValue: false, errorText: 'Not running on a webOS TV' });
            return;
        }
        var bridge = new window.PalmServiceBridge();
        bridges.push(bridge); // keep a reference until the reply arrives
        bridge.onservicecallback = function (msg) {
            var i = bridges.indexOf(bridge);
            if (i >= 0) { bridges.splice(i, 1); }
            var reply;
            try { reply = JSON.parse(msg); } catch (e) { reply = { returnValue: false, errorText: 'Unreadable reply' }; }
            cb(reply);
        };
        bridge.call(uri, JSON.stringify(params));
    }

    // What the TV says about itself, asked from the app.  When the Homebrew
    // Channel runs the script, nyx-cmd and luna-send can come back empty there
    // (a UN7300 on webOS 5 did), so the app hands these over.
    // The app's language goes along too, for the messages the boot hook shows
    var tvEnv = I18N && /^(en|ru|es)$/.test(I18N.lang) ? 'LGU2E_APP_LANG=' + I18N.lang + ' ' : '';
    function tvInfo(cb) {
        luna('luna://com.webos.service.tv.systemproperty/getSystemInfo',
            { keys: ['modelName', 'firmwareVersion', 'boardType'] }, function (r) {
                var ok = function (v) { return typeof v === 'string' && /^[A-Za-z0-9._-]{1,40}$/.test(v); };
                if (r && r.returnValue !== false) {
                    if (ok(r.firmwareVersion)) { tvEnv += 'LGU2E_APP_FIRMWARE=' + shq(r.firmwareVersion) + ' '; }
                    if (ok(r.modelName)) { tvEnv += 'LGU2E_APP_MODEL=' + shq(r.modelName) + ' '; }
                    if (ok(r.boardType)) { tvEnv += 'LGU2E_APP_BOARD=' + shq(r.boardType) + ' '; }
                }
                cb();
            });
    }

    // Run the bundled script as root. cb(ok, stdout, stderr)
    function runScript(args, cb) {
        if (window.LGU2E_DEMO) { window.LGU2E_DEMO(args, cb); return; }
        // The Homebrew Channel starts commands with LG's libsystrim.so preloaded,
        // which makes every program the script runs start about three times
        // slower: status took 5.4 s on a C2, against 1.5 s without it.  The
        // script's short commands don't need it, so it's left out here.
        luna(HBC_EXEC, { command: 'LD_PRELOAD= ' + tvEnv + 'sh ' + shq(SCRIPT) + ' ' + args + ' 2>&1' }, function (r) {
            cb(r.returnValue !== false, r.stdoutString || '', r.errorText || r.stderrString || '');
        });
    }

    // ------------------------------------------------------------------ status

    function refresh(cb) {
        runScript('status --json', function (ok, out, err) {
            var data = null;
            try { data = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { data = null; }
            if (!data) {
                showNoRoot(ok ? T('The script gave an unexpected answer.') : TS(err), ok ? '' : err);
                if (cb) { cb(null); }
                return;
            }
            state = data;
            if (overlayMode === 'setup') { setupDone(); }
            render();
            whatsNew(data);
            if (cb) { cb(data); }
        });
    }

    // A first guess for the report's Result and Options fields, from what the
    // TV shows right now.  The text must match the form's choices exactly;
    // the person can still change them on GitHub.
    function guessResult(s) {
        var a = s.adapter;
        if (!a) { return 'Adapter not detected (no driver)'; }
        if (!s.adapterIsEth0) { return 'Adapter detected but the swap failed'; }
        return a.ip ? 'Works, settings show the wired connection and apps play' : 'Works, but with problems (describe below)';
    }
    function usedOptions(s) {
        var h = s.hook || {}, o = [];
        if (h.state !== 'enabled') { return ''; }
        if (h.watch) { o.push('--watch'); }
        if (h.mac) { o.push('--mac'); }
        if (h.module) { o.push('--module'); }
        if (h.wait && h.wait !== '120') { o.push('--wait'); }
        if (h.wifiFallback) { o.push('--wifi-fallback'); }
        if (h.wifiWake) { o.push('--wifi-wake'); }
        if (h.eeeOff) { o.push('--eee-off'); }
        if (h.blockUpdates) { o.push('--block-updates'); }
        if (h.blockRemoteSupport) { o.push('--block-remote-support'); }
        if (h.blockUpdates && h.blockPhone === false) { o.push('--no-block-phone-updates'); }
        if (h.blockUpdates && h.stopDownloads === false) { o.push('--no-stop-downloads'); }
        return o.length ? o.join(' ') : 'None, the defaults';
    }

    // Whichever port is eth0 right now, and its address
    function eth0(s) {
        var n = [s.adapter, s.builtin];
        for (var i = 0; i < n.length; i++) {
            if (n[i] && n[i].name === 'eth0') { return n[i]; }
        }
        return null;
    }

    // After a switch the network drops for a moment and eth0 has to get an
    // address again (DHCP), which takes a few seconds after the script is
    // done.  Keep checking until it has one, so the screen doesn't stay on
    // "none yet".
    var waitTimer = null;
    function waitForAddress() {
        var tries = 0;
        if (waitTimer) { clearTimeout(waitTimer); }
        function hint(text) {
            if (overlayMode === 'message') { $('overlay-hint').textContent = text; }
        }
        function check() {
            waitTimer = null;
            refresh(function (s) {
                var e = s && eth0(s);
                if (e && e.ip) {
                    hint(T('eth0 is connected at {ip}.  Press OK or BACK to close.', { ip: e.ip.replace(/\/\d+$/, '') }));
                } else if (++tries < 20) {
                    hint(T('Waiting for eth0 to get an address…  Press OK or BACK to close.'));
                    waitTimer = setTimeout(check, 2000);
                } else {
                    hint(T('eth0 has no address after 40 seconds.  Check the cable and the router.  Press OK or BACK to close.'));
                }
            });
        }
        check();
    }

    function showNoRoot(detail, raw) {
        $('dot').className = 'dot dot-bad';
        $('headline').textContent = T('Can\'t reach the TV as root');
        $('subline').textContent = T('This app needs a rooted TV with the Homebrew Channel.  ') + (detail || '');
        $('facts').innerHTML = '';
        $('notes').innerHTML = '';
        // The Homebrew Channel is there and answered, but webOS turned the
        // app away: webOS 26 (issue #32).  Walk through the one-time fix.
        if (/denied method call/i.test(raw || '')) { showSetup(); }
    }

    // ------------------------------------------------------------------ webOS 26 setup

    // webOS 26 no longer lets homebrew apps reach the Homebrew Channel's
    // root service, on Homebrew Channel 0.7.3 and older (0.8.0 has the fix,
    // webosbrew PR #233).  The
    // script's app-access command, run once by the user over SSH, puts
    // this app (only this one) in the Homebrew Channel's group.  Nothing
    // does that on its own: it's the user's choice.  The app can't do that first step itself (it has no way to root
    // yet), so it shows the steps with a QR code for a phone, and checks
    // again every few seconds, carrying on by itself once it can.
    var SETUP_DOC = REPO + '/blob/main/docs/webos-26-setup.md';
    var setupTimer = null;
    var tvIp = '';

    // A translated line with a command in it, the command in <code>
    var CMD = '\u0001';
    function withCode(text, cmd) {
        return esc(text).replace(CMD, '<code>' + esc(cmd) + '</code>');
    }

    function setupBody() {
        var qr = '';
        try {
            var q = window.qrcode(0, 'L');
            q.addData(SETUP_DOC);
            q.make();
            qr = q.createSvgTag({ cellSize: 4, margin: 16, scalable: true });
        } catch (e) { qr = ''; }
        return '<div class="qr qr-setup">' + qr + '<ol class="steps">' +
            '<li>' + esc(T('In the Homebrew Channel, open Settings and turn on SSH Server.')) + '</li>' +
            '<li>' + withCode(T('From a phone or computer on the same network, connect with {cmd}  The password is alpine unless you changed it.', { cmd: CMD }), 'ssh root@' + (tvIp || T('<TV IP address>'))) + '</li>' +
            '<li>' + withCode(T('Run {cmd}', { cmd: CMD }), 'sh ' + SCRIPT + ' app-access') + '</li>' +
            '<li>' + esc(T('That\'s it.  This screen notices and carries on by itself.')) + '</li>' +
            '</ol></div>' +
            '<p class="setup-scan">' + esc(T('Scan the code for these steps on your phone, ready to copy.')) + '</p>';
    }

    function showSetup() {
        if (overlayMode === 'setup') { return; }
        if (overlayMode) { return; }
        overlay('setup', T('One quick setup step for webOS 26'),
            '<p>' + esc(T('webOS 26 keeps homebrew apps away from root on Homebrew Channel 0.7.3 and older.  Update the Homebrew Channel to 0.8.0 or newer and restart the TV, which lets every app back in.  Or one command over SSH lets this app back in.')) + '</p>' + setupBody(),
            T('Checking every few seconds.  OK checks now, BACK exits.'));
        // The TV's address, for the ssh line, if webOS will tell the app
        luna('luna://com.webos.service.connectionmanager/getStatus', {}, function (r) {
            var ip = (r && r.wired && r.wired.ipAddress) || (r && r.wifi && r.wifi.ipAddress) || '';
            if (/^[0-9.]{7,15}$/.test(ip) && overlayMode === 'setup') {
                tvIp = ip;
                $('overlay-body').innerHTML = $('overlay-body').innerHTML.replace(/root@[^<]*/, 'root@' + esc(ip));
            }
        });
        if (!setupTimer) { setupTimer = setInterval(setupCheck, 5000); }
    }

    function setupCheck() {
        if (overlayMode !== 'setup' || document.hidden) { return; }
        refresh();
    }

    function setupDone() {
        if (setupTimer) { clearInterval(setupTimer); setupTimer = null; }
        closeOverlay();
        overlay('message', T('All set'), '<p>' + esc(T('The app can reach root now.')) + '</p>', T('Press OK or BACK to close.'));
        checkUpdate();
    }

    function row(label, value) {
        return '<tr><td>' + esc(label) + '</td><td>' + value + '</td></tr>';
    }

    function render() {
        var s = state;
        var a = s.adapter, b = s.builtin, w = s.wifi, h = s.hook;

        $('meta').textContent = 'v' + s.version + (s.model ? ' · ' + s.model : '') + (s.webos ? ' · ' + s.webos : '');

        // Headline
        var dot = 'dot-ok', head, sub;
        if (a && s.adapterIsEth0) {
            head = T('USB adapter is eth0');
            sub = s.defaultRoute === 'eth0' ? T('Traffic is going over the adapter.') : T('Traffic is going out {route}, not the adapter.', { route: s.defaultRoute || T('nowhere') });
            if (s.defaultRoute !== 'eth0') { dot = 'dot-warn'; }
        } else if (a) {
            head = T('Adapter found, not eth0 yet');
            sub = h.state === 'enabled' ? T('Choose Switch now, or reboot.') : T('Turn on Run at every boot, or choose Switch now.');
            dot = 'dot-warn';
        } else {
            head = T('No USB adapter found');
            sub = T('Plug in a USB Ethernet adapter.  The built-in port keeps working meanwhile.');
            dot = 'dot-warn';
        }
        // The script's v1 advice is for SSH ("Run 'install'").  In the app,
        // point at the Upgrade from v1 row instead.
        var v1 = h.state === 'legacy' || h.state === 'legacy-disabled';
        var issues = s.issues.map(function (i) {
            return v1 && /'install'/.test(i) ? T('An old v1 boot hook is installed.  Choose Upgrade from v1 to replace it, step by step.') : TS(i);
        });
        if (issues.length) { dot = 'dot-bad'; sub = issues[0]; }
        else if (dot === 'dot-ok') { sub += T('  No problems found.'); }
        $('dot').className = 'dot ' + dot;
        $('headline').textContent = head;
        $('subline').textContent = sub;

        // Facts
        var html = '';
        if (a) {
            html += row(T('Adapter'), esc((a.chip || a.id || 'USB') + ' · ' + a.driver) +
                (a.driver === h.driver && h.driver ? ' <span class="ok">✔</span>' : ''));
            // A gigabit adapter on a 100 Mbit/s link (a two-pair cable, a slow
            // router port) or a half-duplex one is worth pointing out
            var slow = a.carrier && ((a.speed && a.speed < 1000) || a.duplex === 'half');
            html += row(T('Link'), (slow ? '<span class="warn">' : '') +
                esc((a.speed ? a.speed + ' ' + T('Mbit/s') : (a.carrier ? T('up') : T('no cable'))) + (a.duplex === 'half' ? T(', half duplex') : '')) +
                (slow ? '</span>' : '') + esc(a.bus ? ' · ' + a.bus : ''));
            html += row(T('Address'), esc(a.ip ? a.ip.replace(/\/\d+$/, '') : T('none yet')));
        } else {
            html += row(T('Adapter'), esc(T('none')));
        }
        if (h.wifiFallbackOn) { html += row(T('Wi-Fi backup'), '<span class="warn">' + esc(T('on, the cable has no link')) + '</span>'); }
        if (s.speed && (s.speed.downMbps || s.speed.upMbps)) {
            html += row(T('Speed'), esc(T('{down} down · {up} up Mbit/s', { down: s.speed.downMbps || '?', up: s.speed.upMbps || '?' }) +
                (s.speed.pingMs !== null ? ' · ' + s.speed.pingMs + ' ' + T('ms') : '')));
        }
        // The cable link dropping in the last day (standby doesn't count)
        var drops = (s.links || []).filter(function (e) { return e.kind === 'lost' && e.at * 1000 > Date.now() - 86400000; });
        if (drops.length) {
            var dl = new Date(drops[0].at * 1000);
            html += row(T('Cable link'), '<span class="warn">' + esc(T('dropped {n} times in the last day, last at {time}', {
                n: drops.length, time: dl.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) })) + '</span>');
        }
        if (b) { html += row(T('Built-in port'), esc(b.name + ' · ' + (b.carrier ? T('cable in') : T('no cable')))); }
        if (w) { html += row('Wi-Fi', w.carrier ? '<span class="warn">' + esc(T('connected')) + '</span>' : esc(T('off'))); }
        var hookText = { enabled: T('on'), disabled: T('off (disabled)'), none: T('off'), broken: T('broken link'), legacy: T('old v1 hook'), 'legacy-disabled': T('old v1 hook') }[h.state] || h.state;
        html += row(T('At boot'), esc(hookText + (h.running ? T(' · running') : '')));
        var last = s.log.length ? s.log[s.log.length - 1] : '';
        // The last log line, unless there are problems or tips to make room for
        if (last && !issues.length && !(s.notes || []).length) { html += row(T('Last log'), esc(last)); }
        $('facts').innerHTML = html;

        // Notes (skip the first issue, already in the subline)
        var notes = issues.slice(1).concat((s.notes || []).map(TS)).slice(0, 4);
        $('notes').innerHTML = notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('');
        // Drop notes from the end until the card fits the screen (a long
        // problem plus several notes can run past it, more so in Russian)
        var card = $('status'), list = $('notes');
        card.className = 'card' + (issues.length || (s.notes || []).length ? ' compact' : '');
        while (list.lastChild && card.scrollHeight > card.clientHeight + 1) { list.removeChild(list.lastChild); }

        // Toggles
        var bootOn = h.state === 'enabled';
        $('tog-boot').className = 'tog' + (bootOn ? ' on' : '');
        $('tog-watch').className = 'tog' + (bootOn && h.watch ? ' on' : '');
        $('tog-wifi').className = 'tog' + (bootOn && h.wifiFallback ? ' on' : '');
        // Wi-Fi wake keeps Wi-Fi connected, so the TV already falls back to it
        $('wifi-hint').textContent = bootOn && h.wifiWake ? T('Wi-Fi wake keeps Wi-Fi connected already') : T('turns Wi-Fi on if the cable stops working, and off when it\'s back');
        $('tog-wake').className = 'tog' + (bootOn && h.wifiWake ? ' on' : '');
        $('tog-updates').className = 'tog' + (bootOn && h.blockUpdates ? ' on' : '');
        // Turn off IPv6: only where it helps, once the speed test found IPv6
        // broken, or when it's on (so it can be turned off again)
        var v6Bad = !!(s.speed && s.speed.ipv6Broken);
        document.querySelector('[data-action="ipv6"]').style.display = (v6Bad || h.ipv6Off) ? '' : 'none';
        $('tog-ipv6').className = 'tog' + (bootOn && h.ipv6Off ? ' on' : '');
        $('ipv6-hint').textContent = !(bootOn && h.ipv6Off) && v6Bad ? T('the last speed test found IPv6 broken here') : T('for networks where IPv6 is broken');
        // Realtek mode: on kernels with their own r8152, or when it's been
        // turned off (so it can be turned back on)
        var rt = s.realtek || {};
        var rtBtn = document.querySelector('[data-action="realtek"]');
        // Only for adapters it can help: Realtek RTL8152 and RTL8153
        var rtFits = rt.r8152 && /^0bda:815[23]$/.test((s.adapter || {}).id || '');
        rtBtn.style.display = (rtFits || rt.result || h.realtekMode === false) ? '' : 'none';
        $('tog-realtek').className = 'tog' + (h.realtekMode !== false ? ' on' : '');
        $('realtek-hint').textContent = rt.result === 'ok' ? T('your adapter is on the TV\'s own r8152') :
            rt.result === 'failed' ? T('r8152 didn\'t take your adapter') : T('uses the TV\'s own Realtek driver');
        var u = s.updates || {};
        // With it on: what it has caught, so there's proof it works
        var blocking = bootOn && h.blockUpdates;
        $('updates-hint').textContent = blocking && u.found && Date.now() - u.found * 1000 < 2592000000 ?
            T('on: removed a firmware update webOS found on {date}, before it could install', { date: new Date(u.found * 1000).toLocaleDateString() }) :
            (blocking && u.tries ? T('on: stopped LG\'s updater reaching its server {n} times, last on {date}', { n: u.tries, date: new Date(u.lastTry * 1000).toLocaleDateString() }) :
            (blocking && h.running ? T('on: update settings off, every LG update server blocked, checked every 10 minutes') :
            (blocking ? T('on: update settings off, every LG update server blocked, checked every 10 minutes from the next restart') :
            (u.hbcBlock === false ? T('off, and the Homebrew Channel\'s block is off too: turns off webOS\'s update settings and blocks every LG update server, so an update can\'t remove root') : T('turns off webOS\'s update settings and blocks every LG update server the Homebrew Channel misses, so an update can\'t remove root for good')))));
        // Phone apps and the download guard: part of Block updates harder,
        // on with it unless turned off
        var phoneOn = blocking && h.blockPhone !== false;
        // Not needed on a TV whose phone connection has no update calls:
        // shown off and dimmed, with why
        var phoneNa = u.phone === 'none';
        $('tog-phone').className = 'tog' + (phoneOn && !phoneNa ? ' on' : '') + (phoneNa ? ' na' : '');
        $('phone-hint').textContent = phoneNa ? T('not needed: this TV\'s phone connection has no firmware update calls, so a phone app can\'t start an update on it') : !blocking ? T('with Block updates harder: stops LG ThinQ on a phone pushing a firmware update straight to the TV, which gets past every server block') :
            (!phoneOn ? T('off by your choice: LG ThinQ on a phone can still push a firmware update to the TV') :
            ({ blocked: T('on: LG ThinQ on a phone can\'t start a firmware update, and casting and the phone remote still work'), next: T('on, takes effect after the next TV restart: the TV\'s phone connection only reads its list when the TV starts'),
                other: T('on: another app, like FW Block, already blocks phone updates') }[u.phone] ||
                T('on, takes effect after the next TV restart: the TV\'s phone connection only reads its list when the TV starts')));
        var dlOn = blocking && h.stopDownloads !== false;
        $('tog-stopdl').className = 'tog' + (dlOn ? ' on' : '');
        $('stopdl-hint').textContent = dlOn && u.cancelled ? T('on: stopped {n} firmware downloads that got past the block, last on {date}', { n: u.cancelled, date: new Date(u.lastCancel * 1000).toLocaleDateString() }) :
            (dlOn ? T('on: every 30 seconds while LG\'s updater is busy, cancels any firmware download.  It never touches an install or a USB update') : T('a last line of defense with Block updates harder: cancels a firmware download that gets past the block, with a message on the TV'));
        // Block LG Remote Support: optional, off by default
        $('tog-remote').className = 'tog' + (bootOn && h.blockRemoteSupport ? ' on' : '');
        $('remote-hint').textContent = bootOn && h.blockRemoteSupport ? T('on: LG Remote Support can\'t connect to this TV, so it can\'t push an update.  Turn it off first if you ever need LG\'s help') : T('optional, off by default: stops LG\'s staff pushing a firmware update during a remote support session.  LG support can\'t connect while it\'s on');
        // Energy Efficient Ethernet off: only where ethtool is there to do it,
        // or when it's on (so it can be turned off again)
        var ee = s.eee || {};
        document.querySelector('[data-action="eee"]').style.display = (ee.tool || h.eeeOff) ? '' : 'none';
        $('tog-eee').className = 'tog' + (bootOn && h.eeeOff ? ' on' : '');
        $('eee-hint').textContent = !ee.tool ? T('needs ethtool from Entware') :
            (ee.state === 'on' ? T('on now, can make the link drop for a moment') : T('for a link that drops for a few seconds'));
        // The faster-driver row only appears when it fits this TV: a driver is
        // known for this exact kernel and the adapter is one it supports, or a
        // driver is already set up (so it can be turned off again).
        var offer = s.driverOffer || 'none';
        var driverBtn = document.querySelector('[data-action="driver"]');
        var hints = {
            available: T('built for this TV\'s kernel'),
            active: h.driver || T('custom module'),
            'wrong-kernel': T('built for an older kernel, not loaded'),
            replace: T('firmware updated, a driver for the new kernel is ready'),
            newer: T('a fixed build of your driver is ready'),
            changed: T('file changed, not loaded'),
            missing: T('module file is missing')
        };
        driverBtn.style.display = offer === 'none' ? 'none' : '';
        $('driver-hint').textContent = hints[offer] || '';
        // The speed test server row says which one is chosen
        var ss = s.speedServer;
        if (ss) {
            $('speedsrv-hint').textContent = ss.choice === 'auto' ? T('Auto: Cloudflare, or the closest other server') : ss.name;
        }
        $('tog-driver').className = 'tog' + (offer !== 'none' && offer !== 'available' && bootOn ? ' on' : '');
        // A new driver to test: shown when there's one for this kernel, or a
        // past test's report to send
        var dt = s.driverTest || {};
        document.querySelector('[data-action="drvtest"]').style.display = dt.available || dt.result ? '' : 'none';
        $('drvtest-hint').textContent = dt.state === 'running' ? T('testing now') :
            (dt.result ? T('last test: {result}', { result: T(DT_SAYS[dt.result] || dt.result) }) :
                (dt.adapterOk ? T('built for this TV\'s kernel, helps add support') : T('plug in an adapter it supports to try it')));
        // Link health says when the cable link has been dropping
        $('health-hint').textContent = drops.length ? T('dropped {n} times in the last day: see when, and the error counts', { n: drops.length }) :
            T('how long the cable link has been up, with its drops and errors');
        // Speed test history: only once there's a result
        var sh = s.speedHistory || [];
        document.querySelector('[data-action="speedhist"]').style.display = sh.length ? '' : 'none';
        if (sh.length) {
            $('speedhist-hint').textContent = T('last: {down} down / {up} up Mbit/s on {date}, and the ones before',
                { down: sh[0].downMbps, up: sh[0].upMbps, date: new Date(sh[0].at * 1000).toLocaleDateString() });
        }
        $('lang-hint').textContent = I18N ? I18N.label() : 'English';
        renderUpdate();
        if (current >= buttons().length) { current = buttons().length - 1; }
    }

    // The menu's tabs: only the open tab's rows show, a tab with no rows to
    // show is hidden, and More gets a dot when an update is waiting there.
    // Also run before the first status, while the app is still checking.
    var TABS = ['conn', 'fw', 'driver', 'net', 'more'];
    // True while the focus is up on the tab bar (UP from a tab's first row)
    var onTabs = false;
    var tab = 'conn';
    function tabRows(t) {
        return Array.prototype.slice.call(document.querySelectorAll('.btn[data-tab="' + t + '"]')).filter(function (b) {
            return b.style.display !== 'none';
        });
    }
    function visibleTabs() { return TABS.filter(function (t) { return tabRows(t).length > 0; }); }
    function fitRows() {
        var vis = visibleTabs();
        if (vis.indexOf(tab) < 0) { tab = vis[0] || 'conn'; }
        Array.prototype.slice.call(document.querySelectorAll('.tab')).forEach(function (el) {
            var t = el.getAttribute('data-tab');
            var news = t === 'more' && tabRows('more').some(function (b) { return b.className.indexOf('btn-update') >= 0; });
            el.className = 'tab' + (t === tab ? ' on' : '') + (news ? ' news' : '') + (vis.indexOf(t) < 0 ? ' gone' : '');
        });
        Array.prototype.slice.call(document.querySelectorAll('.btn')).forEach(function (b) {
            b.className = b.className.replace(/ ?off-tab/g, '') + (b.getAttribute('data-tab') === tab ? '' : ' off-tab');
        });
        // Longer tab names (Spanish, Russian) step the tab text down to fit
        var bar = $('tabs');
        bar.className = 'tabs';
        if (bar.scrollWidth > bar.clientWidth) { bar.className = 'tabs small'; }
        if (bar.scrollWidth > bar.clientWidth) { bar.className = 'tabs smaller'; }
    }
    // Open tab T (or the next visible one in a direction).  The focus stays
    // on the tab bar if it's there, or goes to the tab's first row.
    function openTab(t) {
        tab = t;
        current = 0;
        fitRows();
        focusCurrent();
    }
    function stepTab(dir) {
        var vis = visibleTabs();
        var i = vis.indexOf(tab) + dir;
        if (i >= 0 && i < vis.length) { openTab(vis[i]); }
    }
    // Focus the row for ACTION, on its own tab
    function focusAction(action) {
        var b = document.querySelector('[data-action="' + action + '"]');
        if (!b) { return; }
        tab = b.getAttribute('data-tab');
        onTabs = false;
        fitRows();
        current = Math.max(buttons().indexOf(b), 0);
        focusCurrent();
    }

    // The update row only shows when a newer release is out.  If the
    // Homebrew Channel knows this app's repo, updates come from there.
    function renderUpdate() {
        var h = state ? state.hook : {};
        document.querySelector('[data-action="upgrade"]').style.display =
            h.state === 'legacy' || h.state === 'legacy-disabled' ? '' : 'none';
        var btn = document.querySelector('[data-action="update"]');
        var show = !!(upd && upd.newer);
        btn.style.display = show ? '' : 'none';
        fitRows();
        if (!show) { return; }
        $('update-title').textContent = T('Update to v{v}', { v: upd.latest });
        $('update-hint').textContent = upd.source === 'homebrew' ? T('opens the Homebrew Channel') : T('you have v{v}, downloads and installs', { v: upd.current });
    }

    function checkUpdate() {
        runScript('update --check --json', function (ok, out) {
            var d = null;
            try { d = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { d = null; }
            upd = d;
            if (state) { render(); }
            if (!overlayMode) { focusCurrent(); }
        });
    }

    // ------------------------------------------------------------------ overlay

    function overlay(mode, title, bodyHtml, hint) {
        overlayMode = mode;
        $('overlay-title').textContent = title;
        $('overlay-body').innerHTML = bodyHtml;
        $('overlay-hint').textContent = hint || '';
        $('overlay').className = 'overlay';
    }
    function closeOverlay() {
        overlayMode = null;
        liveTok++; // stops Live traffic's updates
        onConfirm = null;
        $('overlay').className = 'overlay hidden';
        focusCurrent();
    }

    // Run a script command with a busy screen, then show its output
    function act(title, args, after, network) {
        if (busy) { return; }
        busy = true;
        overlay('busy', title, '<span class="spinner"></span>' + esc(T('Working on it…  The picture is fine, only the network is changing.')), '');
        runScript(args, function (ok, out, err) {
            busy = false;
            var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim();
            var lines = text.split('\n');
            if (lines.length > 14) { lines = lines.slice(lines.length - 14); }
            overlay('message', ok ? T('{title}: done', { title: title }) : T('{title}: something went wrong', { title: title }),
                '<pre>' + esc(lines.join('\n')) + '</pre>', T('Press OK or BACK to close.'));
            if (network && ok) { waitForAddress(); } else { refresh(); }
            if (after) { after(ok, text); }
        });
    }

    // A step of a walk-through: an HTML list, OK goes on, BACK cancels
    function stepThen(title, html, hint, fn) {
        onConfirm = fn;
        overlay('confirm', title, html, hint);
    }
    function li(cls, html) { return '<li class="' + cls + '">' + html + '</li>'; }
    // Translated text with {eth0}, {file}, {name}, {link} as code
    function TC(text, vars) {
        var v = vars || {}, out = esc(T(text));
        v.eth0 = v.eth0 || 'eth0';
        return out.replace(/\{(\w+)\}/g, function (m, k) { return k in v ? '<code>' + esc(v[k]) + '</code>' : m; });
    }

    // CHANGELOG markdown, short: the bold lead if there is one, else the
    // first sentence.  Links become plain text, since there's no browser.
    function mdShort(s) {
        var b = s.match(/^\*\*(.+?)\*\*/);
        var t = b ? b[1] : s.replace(/^(.+?\.)\s.*$/, '$1');
        return esc(t.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1'))
            .replace(/`([^`]+)`/g, '<code>$1</code>');
    }

    // A changelog's sections as the What's new list: the bold lead of each
    // item, up to max of them
    function wnList(secs, max) {
        var html = '', n = 0;
        secs.forEach(function (sec) {
            if (n >= max || !sec.items.length) { return; }
            html += '<div class="walk-h">' + esc(T(sec.title)) + '</div><ul class="walk">';
            sec.items.forEach(function (it) { if (n < max) { html += li(sec.title === 'Fixed' ? 'ok' : '', mdShort(it)); n++; } });
            html += '</ul>';
        });
        return html;
    }
    // This version's sections, in the app's language when its changelog has them
    function wnSections() {
        var wn = window.LGU2E_WHATSNEW;
        if (!wn) { return null; }
        return (I18N && wn.i18n && wn.i18n[I18N.lang]) || wn.sections;
    }
    // A key or click in the first moments doesn't close What's new: a button
    // still held from before the app opened shouldn't hide it unseen
    var wnGuardUntil = 0;
    function showWhatsNew(title) {
        var secs = wnSections();
        if (!secs) { return false; }
        overlay('message', title, wnList(secs, 8),
            T('Press OK or BACK to close.  Full notes: github.com/ohmybahgosh/LG-USB-2-ETH0/releases'));
        wnGuardUntil = Date.now() + 1500;
        return true;
    }

    // After an update, the first time the new version opens, show what
    // changed.  The last version seen is kept in the app's own storage, and
    // only moved on once What's new has shown: when something else is on
    // screen, it waits for the next status refresh.  Any version can see it
    // again with the What's new row.
    var whatsNewDone = false;
    function whatsNew(s) {
        if (whatsNewDone || !s) { return; }
        var wn = window.LGU2E_WHATSNEW, v = s.version, seen = null;
        try { seen = window.localStorage.getItem('lgu2e.seenVersion'); } catch (e) { whatsNewDone = true; return; }
        var mark = function () { try { window.localStorage.setItem('lgu2e.seenVersion', v); } catch (e) { /* shown again next time */ } };
        // Updated in the app (the script logs it), or through the Homebrew Channel
        var updated = s.updatedTo === v || (seen && seen !== v);
        if (!updated || seen === v || !wn || wn.version !== v) { mark(); whatsNewDone = true; return; }
        if (overlayMode || busy) { return; }
        if (showWhatsNew(T('Updated to v{v}: what\'s new', { v: v }))) { mark(); whatsNewDone = true; }
    }

    // a > b for versions like 2.11.51
    function verGt(a, b) {
        var x = String(a).split('.'), y = String(b).split('.');
        for (var i = 0; i < Math.max(x.length, y.length); i++) {
            var p = parseInt(x[i] || '0', 10), q = parseInt(y[i] || '0', 10);
            if (p !== q) { return p > q; }
        }
        return false;
    }
    // Every changelog section newer than from, up to and including to, from
    // the changelog text, newest first: [{ title, items }] merged by title
    function changesSince(text, from, to) {
        var out = [], byTitle = {}, on = false, cur = null;
        String(text).split('\n').forEach(function (line) {
            var v = line.match(/^## \[([0-9.]+)\]/);
            if (/^## /.test(line)) { on = !!v && verGt(v[1], from) && !verGt(v[1], to); cur = null; return; }
            if (!on) { return; }
            var h = line.match(/^### (.+)/);
            if (h) {
                var title = h[1].trim();
                if (!byTitle[title]) { byTitle[title] = { title: title, items: [] }; out.push(byTitle[title]); }
                cur = byTitle[title];
                return;
            }
            var it = line.match(/^- (.+)/);
            if (it && cur) { cur.items.push(it[1].trim()); }
        });
        return out;
    }
    // The new version's changelog from GitHub, in the app's language when
    // there's one: cb(sections or null).  Gives up after 8 seconds.
    function fetchChanges(from, to, cb) {
        var file = I18N && (I18N.lang === 'ru' || I18N.lang === 'es') ? 'docs/changelog.' + I18N.lang + '.md' : 'CHANGELOG.md';
        var done = false, finish = function (r) { if (!done) { done = true; cb(r); } };
        try {
            var x = new XMLHttpRequest();
            x.open('GET', 'https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/v' + to + '/' + file, true);
            x.timeout = 8000;
            x.onload = function () {
                var secs = x.status === 200 ? changesSince(x.responseText, from, to) : [];
                finish(secs.length ? secs : null);
            };
            x.onerror = x.ontimeout = function () { finish(null); };
            x.send();
        } catch (e) { finish(null); }
        setTimeout(function () { finish(null); }, 9000);
    }

    // Step 3 of the walk-through: upgrade, then check the result
    function upgradeNow() {
        busy = true;
        overlay('busy', T('Upgrade from v1'), '<span class="step-of">' + esc(T('Step 3 of 3 · upgrading')) + '</span><span class="spinner"></span>' + esc(T('Replacing the boot hook…')), '');
        runScript('install -y', function (ok, out, err) {
            refresh(function (s) {
                busy = false;
                var h = s ? s.hook : {};
                var done = ok && s && h.state === 'enabled' && !!h.link;
                var checks = '';
                if (s) {
                    checks += h.state === 'enabled' && h.link ? li('ok', esc(T('The boot hook is this version\'s now: {link}')).replace('{link}', '<code>' + esc(h.link) + '</code>')) : li('warn', esc(T('The boot hook isn\'t this version\'s yet.')));
                    checks += h.state !== 'legacy' && h.state !== 'legacy-disabled' ? li('ok', esc(T('The old v1 file is gone.'))) : li('warn', esc(T('The old v1 file is still there.')));
                    checks += s.adapter && s.adapterIsEth0 ? li('ok', TC('Your USB adapter is still {eth0}.')) : li('', TC('The adapter becomes {eth0} at the next boot, or choose Switch now.'));
                    checks += li('ok', TC('Run at every boot is on.  Your settings are in {file}.', { file: '/var/lib/webosbrew/lg-usb-2-eth0.conf' }));
                }
                var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim().split('\n').slice(-8).join('\n');
                overlay('message', done ? T('Upgrade from v1: done') : T('Upgrade from v1: something went wrong'),
                    '<span class="step-of">' + esc(done ? T('Step 3 of 3 · all done') : T('Step 3 of 3 · check this')) + '</span><ul class="walk">' + checks + '</ul>' +
                    (done ? '' : '<pre>' + esc(text) + '</pre>'),
                    done ? T('Press OK or BACK to close.  Nothing else to do.') : T('Press OK or BACK to close.  Report for GitHub makes a report you can send.'));
            });
        });
    }

    // ------------------------------------------------------------------ driver test

    // test-driver's results, in the app's words and the report form's
    var DT_SAYS = {
        works: 'it works', 'no-internet': 'link, but not online', 'no-link': 'no cable link',
        'not-used': 'adapter didn\'t move to it', 'no-load': 'didn\'t load', crashed: 'the TV restarted'
    };
    var DT_FORM = {
        works: 'Works, online on the new driver',
        'no-internet': 'On the new driver with a cable link, but not online',
        'no-link': 'On the new driver, but no cable link',
        'not-used': 'Driver loaded, but the adapter didn\'t move to it',
        'no-load': 'Driver didn\'t load',
        crashed: 'TV froze or restarted'
    };

    // A QR code for a GitHub form link.  The GitHub phone apps open
    // github.com/<owner>/<repo> links as a blank issue, so it goes through
    // /login, which the phone's browser opens and forwards to the form.
    function formQr(form) {
        try {
            var qr = window.qrcode(0, 'L');
            qr.addData('https://github.com/login?return_to=' + encodeURIComponent(form));
            qr.make();
            return qr.createSvgTag({ cellSize: 4, margin: 16, scalable: true });
        } catch (e) {
            return '';
        }
    }

    // The last test's report, as a QR code for a filled-in driver test form
    function drvtestResult(again) {
        runScript('test-driver --last', function (ok, out) {
            var text = (out || '').replace(/\x1b\[[0-9;]*m/g, '');
            var m = text.match(/```\s*\n([\s\S]*?)\n```/);
            var report = (m ? m[1] : text).replace(/ {2,}/g, ' ').trim();
            function line(k) { var r = report.match(new RegExp('^' + k + ':\\s*(.*)$', 'm')); return r ? r[1].trim() : ''; }
            var result = line('Result'), s = state || {};
            // The form has its own model field.  Up to 6 kernel log lines, so
            // the QR code stays easy to scan.
            var lines = report.split('\n').filter(function (l) { return !/^Model:/.test(l); });
            var kl = lines.indexOf('Kernel log:');
            if (kl >= 0) { lines = lines.slice(0, kl + 7); }
            var short = lines.join('\n');
            var form = REPO_PATH + '/issues/new?template=driver-test.yml' +
                '&title=' + q('[Driver test] ' + (s.model || 'LG TV') + ' on ' + line('Kernel')) +
                '&model=' + q(s.model || '') +
                '&kernel=' + q(line('Kernel') + ', ' + line('Chip')) +
                '&adapter=' + q(line('Adapter')) +
                (DT_FORM[result] ? '&result=' + q(DT_FORM[result]) : '') +
                '&report=' + q(short);
            var svg = formQr(form);
            var said = result === 'works' ? T('It works!  ') : (result === 'crashed' ? T('The TV restarted during the test, so this driver doesn\'t fit as it is.  ') : '');
            var html = '<div class="qr">' + svg + '<div>' + esc(said) + esc(T('Scan this with your phone to send the result on GitHub, already filled in.  Every result helps, good or bad.  MAC and IP addresses are left out.')) + ' ' + esc(T('If your phone opens the GitHub app, open the link in your browser instead, or the form arrives empty.')) + '<br><br><pre>' +
                esc(report.split('\n').slice(0, 10).join('\n')) + '</pre></div></div>';
            if (again) {
                stepThen(T('Driver test: {result}', { result: T(DT_SAYS[result] || result) }), html, T('Press OK to test again, or BACK to close.'), drvtestStart);
            } else {
                overlay('message', T('Driver test: {result}', { result: T(DT_SAYS[result] || result) }), html,
                    result === 'works' ? T('Press OK or BACK to close.  The driver stays in use until the next restart.') : T('Press OK or BACK to close.'));
            }
        });
    }

    // The first time the app opens on a TV with a driver to test, say so,
    // once.  Remembered per driver folder in the app's own storage, so a
    // newer build for this kernel is mentioned again.  Skipped when What's
    // new is on screen; it shows the next time the app opens instead.
    function drvtestOffer(s) {
        var dt = (s && s.driverTest) || {};
        if (!dt.available || dt.result || dt.state === 'running' || !dt.folder || overlayMode) { return; }
        try {
            if (window.localStorage.getItem('lgu2e.drvtestOffered') === dt.folder) { return; }
            window.localStorage.setItem('lgu2e.drvtestOffered', dt.folder);
        } catch (e) { return; }
        var html = '<ul class="walk">' +
            li('ok', esc(s.adapter && s.adapter.driver ? T('There\'s a driver built for this TV\'s kernel from LG\'s own source, and nobody with this kernel has tried it yet.') :
                T('There\'s a driver built for this TV\'s kernel from LG\'s own source, so your adapter could work, and nobody with this kernel has tried it yet.'))) +
            li('', esc(T('Testing it takes a minute: it\'s only loaded until the next restart, and you send the result with your phone.  That\'s how it gets offered to everyone with this TV.'))) +
            li('', esc(dt.adapterOk ? T('Your adapter is one it supports.') : T('Plug in an adapter it supports first: Realtek (RTL8152, RTL8153 or RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 or Microchip LAN78xx, whichever the new driver is for.'))) +
            li('', esc(T('It stays in the menu as Test a new driver, on the Driver tab, so you can do it any time.'))) + '</ul>';
        if (dt.adapterOk) {
            stepThen(T('A new driver to test'), html, T('Press OK to test it now, or BACK for later.'), drvtestStart);
        } else {
            overlay('message', T('A new driver to test'), html, T('Press OK or BACK to close.'));
        }
    }

    // Start a test, then follow it until it's done (it runs detached, since
    // moving the adapter takes the network down for a moment)
    function drvtestStart() {
        var dt = (state && state.driverTest) || {};
        if (!dt.adapterOk) {
            overlay('message', T('Test a new driver'), esc(T('Plug in a USB adapter it supports first: Realtek (RTL8152, RTL8153 or RTL8156), ASIX AX88179, Aquantia AQC111, Davicom DM9601 or Microchip LAN78xx, whichever the new driver is for.')), T('Press OK or BACK to close.'));
            return;
        }
        confirmThen(T('Test a new driver?'),
            T('There\'s a driver built for this TV\'s kernel from LG\'s own source, that hasn\'t run on a TV with this kernel yet.  The test downloads it, checks its checksum, loads it until the next restart only, moves the adapter to it and checks it gets online.  The network drops for a moment.  If it doesn\'t fit, the TV can freeze or restart: restart it (unplug it if needed) and open the app again to send that result too.'),
            function () {
                busy = true;
                overlay('busy', T('Testing the new driver'), '<span class="spinner"></span>' + esc(T('Downloading and checking it, then moving the adapter over.  This takes up to a minute.')), '');
                runScript('test-driver -y --no-wait', function (ok, out, err) {
                    var tries = 0;
                    function poll() {
                        refresh(function (s) {
                            var st = s && s.driverTest ? s.driverTest.state : '';
                            if (st === 'running' && tries++ < 40) { setTimeout(poll, 3000); return; }
                            busy = false;
                            if (st === 'done') { drvtestResult(false); return; }
                            var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim().split('\n').slice(-12).join('\n');
                            overlay('message', st === 'running' ? T('Driver test: still running') : T('Driver test: didn\'t start'),
                                '<pre>' + esc(text) + '</pre>', T('Press OK or BACK to close.'));
                        });
                    }
                    setTimeout(poll, 2000);
                });
            });
    }

    // The speed test server list: UP and DOWN move, OK chooses, BACK cancels
    var pickItems = [], pickAt = 0;
    function pick(items, chosen, note) {
        pickItems = items;
        pickAt = 0;
        var html = (note ? '<div class="speed-meta warn pick-note">' + esc(note) + '</div>' : '') + '<div class="pick-list">';
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            if (it.id === chosen) { pickAt = i; }
            html += '<div class="pick' + (it.bad ? ' bad' : '') + (it.id === chosen ? ' chosen' : '') + '" tabindex="0" data-i="' + i + '"><span><b>' +
                esc(it.name) + '</b>' + (it.sub ? '<small>' + esc(it.sub) + '</small>' : '') + '</span>' +
                (typeof it.ms === 'number' ? '<em>' + esc(it.ms + ' ' + T('ms')) + '</em>' : '') + '</div>';
        }
        html += '</div>';
        overlay('pick', T('Speed test server'), html, T('Up and down to move, OK to choose, BACK to cancel.'));
        Array.prototype.slice.call(document.querySelectorAll('.pick')).forEach(function (el) {
            el.addEventListener('mouseover', function () { pickAt = +el.getAttribute('data-i'); pickFocus(); });
            el.addEventListener('click', function (e) { e.stopPropagation(); pickAt = +el.getAttribute('data-i'); pickChoose(); });
        });
        pickFocus();
    }
    function pickFocus() {
        var el = document.querySelectorAll('.pick')[pickAt];
        if (el) { el.focus(); }
    }
    function pickChoose() {
        var it = pickItems[pickAt];
        if (!it || busy) { return; }
        busy = true;
        overlay('busy', T('Speed test server'), '<span class="spinner"></span>' + esc(T('Saving…')), '');
        runScript('speed-server --json \'' + String(it.id).replace(/'/g, '') + '\'', function (ok, out, err) {
            busy = false;
            var d = null;
            try { d = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { d = null; }
            if (!d || !d.choice) { pickFailed(out || err); return; }
            overlay('message', T('Speed test server: {name}', { name: d.choice === 'auto' ? T('Auto') : d.name }),
                esc(T('The next speed test uses it.')), T('Press OK or BACK to close.'));
            refresh();
        });
    }
    function pickFailed(text) {
        overlay('message', T('Speed test server: something went wrong'),
            '<pre>' + esc((text || T('No answer from the script.')).replace(/\x1b\[[0-9;]*m/g, '').trim()) + '</pre>', T('Press OK or BACK to close.'));
    }

    function confirmThen(title, text, fn) {
        onConfirm = fn;
        overlay('confirm', title, esc(text), T('Press OK to go ahead, or BACK to cancel.'));
    }

    // ------------------------------------------------------------------ network tab

    // A script command's JSON answer, or null
    function runJson(args, cb) {
        runScript(args, function (ok, out, err) {
            var d = null;
            try { d = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { d = null; }
            cb(d, out || err);
        });
    }
    // A time span for people: 3 d 4 h, 2 h 10 min, 5 min
    function span(secs) {
        var d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60);
        if (d) { return T('{d} d {h} h', { d: d, h: h }); }
        if (h) { return T('{h} h {m} min', { h: h, m: m }); }
        return T('{m} min', { m: Math.max(m, 1) });
    }
    function when(at) {
        var d = new Date(at * 1000);
        return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
    function kv(rows) {
        return '<table class="kv">' + rows.map(function (r) { return r ? row(r[0], r[1]) : ''; }).join('') + '</table>';
    }
    // Speeds with one decimal under 10, whole numbers above
    function mbps(v) { return v >= 10 ? String(Math.round(v)) : (Math.round(v * 10) / 10).toFixed(1); }
    // A byte count: 1.2 GB, 340 MB
    function bytes(b) { return b >= 1e9 ? (b / 1e9).toFixed(1) + ' GB' : (b >= 1e6 ? Math.round(b / 1e6) + ' MB' : Math.round(b / 1e3) + ' KB'); }
    function failed(title, text) {
        busy = false;
        overlay('message', T('{title}: something went wrong', { title: title }),
            '<pre>' + esc((text || T('No answer from the script.')).replace(/\x1b\[[0-9;]*m/g, '').trim()) + '</pre>', T('Press OK or BACK to close.'));
    }

    // What each connection check step found, in plain words
    function checkLine(s) {
        var v = s.value || '', ms = s.ms;
        var say = {
            'cable.ok': v ? T('Cable link at {speed} Mbit/s', { speed: v }) : T('Cable link'),
            'cable.fail': T('No cable link.  Check the cable is in at both ends, or try another cable or router port.'),
            'address.ok': T('Address {ip} from the router', { ip: v }),
            'address.fail': v ? T('The router\'s DHCP didn\'t answer, so the TV gave itself {ip}, which goes nowhere.  Restart the router.', { ip: v }) :
                T('No address yet: the router\'s DHCP didn\'t answer.  Restart the router, or wait a minute and check again.'),
            'router.ok': ms !== null && ms !== undefined ? T('Router {ip} answers in {ms} ms', { ip: v, ms: ms }) : T('Router {ip} answers', { ip: v }),
            'router.fail': v ? T('Router {ip} doesn\'t answer.  Restart it, and check the cable goes to it.', { ip: v }) : T('The router didn\'t give eth0 a gateway.'),
            'dns.ok': T('Names resolve: www.google.com is {ip}', { ip: v }),
            'dns.fail': T('Names don\'t resolve, so apps can\'t find their servers.  The TV asks {dns}.  Restart the router, or set another DNS server on it.', { dns: v.replace(/,/g, ', ') || T('no DNS server') }),
            'internet.ok': ms !== null && ms !== undefined ? T('Internet works, {ms} ms to Google', { ms: ms }) : T('Internet works'),
            'internet.fail': T('The router answers, but the internet doesn\'t.  Check the router\'s own connection.'),
            'route.ok': T('Apps use eth0'),
            'route.warn': T('Apps use {nic}, not eth0.  Choose Switch now, or check Wi-Fi as a backup.', { nic: v }),
            'route.fail': T('There\'s no route out, so nothing reaches the internet.'),
            'updates.ok': T('LG\'s update servers are blocked'),
            'updates.fail': T('Block updates harder has gaps ({gaps}).  It fixes them within 10 minutes, or turn it off and on.', { gaps: v.replace(/,/g, ', ') }),
            'phone.ok': T('Phone apps can\'t start an update'),
            'phone.warn': T('Phone apps are blocked after the next TV restart'),
            'phone.fail': T('Phone apps can still start an update until the TV restarts.  The block is on, and the TV\'s phone connection only reads its list when the TV starts.'),
            'remote.ok': T('LG Remote Support is blocked'),
            'remote.fail': T('Block LG Remote Support has gaps ({gaps}).  It fixes them within 10 minutes, or turn it off and on.', { gaps: v.replace(/,/g, ', ') })
        };
        var skip = { address: T('Address: skipped'), router: T('Router: skipped'), dns: T('DNS: skipped'), internet: T('Internet: skipped') };
        if (s.result === 'skip') { return li('skip', esc(skip[s.id] || s.id)); }
        var cls = s.result === 'ok' ? 'ok' : (s.result === 'warn' ? 'warn' : 'bad');
        return li(cls, esc(say[s.id + '.' + s.result] || (s.id + ': ' + s.result)));
    }
    function netCheck() {
        if (busy) { return; }
        busy = true;
        overlay('busy', T('Check connection'), '<span class="spinner"></span>' + esc(T('Checking the cable, router, DNS and internet…')), '');
        runJson('netcheck --json', function (d, raw) {
            if (!d || !d.steps) { failed(T('Check connection'), raw); return; }
            busy = false;
            var bad = d.steps.filter(function (s) { return s.result === 'fail'; });
            var warn = d.steps.filter(function (s) { return s.result === 'warn'; });
            var title = bad.length ? T('Check connection: a problem found') : (warn.length ? T('Check connection: works, with a warning') : T('Check connection: all good'));
            stepThen(title, '<ul class="walk check">' + d.steps.map(checkLine).join('') + '</ul>',
                T('Press OK to check again, or BACK to close.'), netCheck);
        });
    }

    // Network details: what eth0 is using
    function netInfo() {
        if (busy) { return; }
        busy = true;
        overlay('busy', T('Network details'), '<span class="spinner"></span>' + esc(T('Reading the network setup.')), '');
        runJson('netinfo --json', function (d, raw) {
            if (!d || !d.interface) { failed(T('Network details'), raw); return; }
            busy = false;
            var ip = d.ipv4 ? d.ipv4.split('/') : null;
            var how = d.method === 'dhcp' ? T('from the router (DHCP)') : (d.method === 'manual' ? T('set by hand') : '');
            var link = d.speed ? d.speed + ' ' + T('Mbit/s') + (d.duplex === 'half' ? T(', half duplex') : '') : T('no cable');
            overlay('message', T('Network details'), kv([
                [T('Connection'), esc(d.interface + ' · ' + link)],
                [T('Address'), ip ? esc(ip[0]) + ' <span class="dim">' + esc('/' + ip[1] + (how ? ' · ' + how : '')) + '</span>' : esc(T('none yet'))],
                [T('Router'), esc(d.gateway || T('none'))],
                [T('DNS servers'), esc(d.dns.length ? d.dns.join(', ') : T('none'))],
                [T('IPv6'), esc(d.ipv6.length ? d.ipv6.map(function (a) { return a.replace(/\/\d+$/, ''); }).join(', ') : T('none'))],
                [T('MAC address'), '<code>' + esc(d.mac) + '</code>'],
                [T('MTU'), esc(String(d.mtu || '?'))],
                [T('Apps use'), d.defaultRoute === d.interface ? esc(d.defaultRoute) : '<span class="warn">' + esc(d.defaultRoute || T('nothing')) + '</span>']
            ]) + '<div class="speed-meta">' + esc(T('To keep this address, reserve the MAC address for it in your router\'s DHCP settings.')) + '</div>',
                T('Press OK or BACK to close.'));
        });
    }

    // Link health: how long the cable link has been up, its drops and errors
    var LINK_SAYS = {
        lost: 'Cable link lost', back: 'Cable link back', plugged: 'Adapter plugged in', unplugged: 'Adapter unplugged',
        hung: 'Adapter stopped answering, restarted it', generic: 'Adapter on the generic driver, moved it back'
    };
    function linkHealth() {
        if (busy) { return; }
        busy = true;
        overlay('busy', T('Link health'), '<span class="spinner"></span>' + esc(T('Reading the network setup.')), '');
        runJson('netinfo --json', function (d, raw) {
            if (!d || !d.health) { failed(T('Link health'), raw); return; }
            busy = false;
            var h = d.health, now = Date.now() / 1000;
            var errs = h.rxErrors + h.txErrors;
            var verdict = !h.carrier ? li('bad', esc(T('No cable link right now.'))) :
                (h.dropsDay ? li('warn', esc(T('The link dropped {n} times in the last day.  Turning off Energy Efficient Ethernet often helps, or try another cable.', { n: h.dropsDay }))) :
                (errs ? li('warn', esc(T('No drops in the last day, but {n} errors since the TV started.  A cable or adapter going bad shows here first.', { n: errs }))) :
                li('ok', esc(T('Healthy: no drops in the last day and no errors.')))));
            var events = (state && state.links || []).slice(0, 5).map(function (e) {
                var extra = e.kind === 'back' && /^\d+/.test(e.detail) ? T(' after {s} s', { s: e.detail.split(' ')[0] }) : '';
                return '<tr><td>' + esc(when(e.at)) + '</td><td>' + esc(T(LINK_SAYS[e.kind] || e.kind) + extra) + '</td></tr>';
            }).join('');
            overlay('message', T('Link health'), '<ul class="walk">' + verdict + '</ul>' + kv([
                [T('Link up for'), h.upSince ? esc(span(now - h.upSince)) + ' <span class="dim">' + esc(T('since {time}', { time: when(h.upSince) })) + '</span>' : esc(T('no cable'))],
                [T('Drops'), esc(T('{day} in the last day, {week} in the last week', { day: h.dropsDay, week: h.dropsWeek }))],
                [T('Errors'), (errs ? '<span class="warn">' : '') + esc(T('{rx} in, {tx} out', { rx: h.rxErrors, tx: h.txErrors }) +
                    (h.rxCrc ? T(' ({n} bad checksums)', { n: h.rxCrc }) : '')) + (errs ? '</span>' : '')],
                [T('Packets'), esc(T('{rx} in, {tx} out', { rx: h.rxPackets.toLocaleString(), tx: h.txPackets.toLocaleString() }))],
                h.eee ? [T('Energy Efficient Ethernet'), esc(h.eee === 'on' ? T('on') : T('off'))] : null
            ]) + (events ? '<div class="walk-h">' + esc(T('Recent changes')) + '</div><table class="hist events">' + events + '</table>' : ''),
                T('Press OK or BACK to close.'));
        });
    }

    // Live traffic: each connection's speed right now, every second or so,
    // until it's closed
    var liveTok = 0;
    function liveTraffic() {
        if (busy) { return; }
        var tok = ++liveTok, past = [], first = true;
        overlay('message', T('Live traffic'), '<span class="spinner"></span>' + esc(T('Measuring…')), T('Updates every second.  Press OK or BACK to close.'));
        function draw(d) {
            var main = null, others = [];
            d.interfaces.forEach(function (i) { if (i.name === d.defaultRoute && !main) { main = i; } else { others.push(i); } });
            if (!main) { main = others.shift(); }
            past.push(main.rxMbps);
            if (past.length > 40) { past.shift(); }
            var top = Math.max.apply(null, past.concat([1]));
            // 40 slots, filling in from the right
            var bars = new Array(41 - past.length).join('<i class="e"></i>') +
                past.map(function (v) { return '<i style="height:' + Math.max(4, Math.round(v / top * 100)) + '%"></i>'; }).join('');
            var rest = others.map(function (i) {
                return '<tr><td>' + esc(i.name) + '</td><td>' + esc(T('{down} down · {up} up Mbit/s', { down: mbps(i.rxMbps), up: mbps(i.txMbps) })) + '</td></tr>';
            }).join('');
            $('overlay-body').innerHTML = '<div class="speed">' +
                '<div class="tile"><small>' + esc(T('Download')) + ' · ' + esc(main.name) + '</small><b>' + esc(mbps(main.rxMbps)) + '</b><span>' + esc(T('Mbit/s')) + '</span></div>' +
                '<div class="tile"><small>' + esc(T('Upload')) + ' · ' + esc(main.name) + '</small><b>' + esc(mbps(main.txMbps)) + '</b><span>' + esc(T('Mbit/s')) + '</span></div></div>' +
                '<div class="spark">' + bars + '</div>' +
                '<div class="speed-meta">' + esc(T('{down} down and {up} up since the TV started.', { down: bytes(main.rxBytes), up: bytes(main.txBytes) })) +
                (main.name !== d.defaultRoute && d.defaultRoute ? ' <span class="warn">' + esc(T('Apps use {nic} right now, not {main}.', { nic: d.defaultRoute, main: main.name })) + '</span>' : '') + '</div>' +
                (rest ? '<table class="hist">' + rest + '</table>' : '');
        }
        function tick() {
            runJson('traffic --json', function (d, raw) {
                if (tok !== liveTok || overlayMode !== 'message') { return; }
                if (!d || !d.interfaces || !d.interfaces.length) {
                    if (first) { $('overlay-body').innerHTML = '<pre>' + esc((raw || T('No answer from the script.')).replace(/\x1b\[[0-9;]*m/g, '').trim()) + '</pre>'; }
                    return;
                }
                first = false;
                draw(d);
                tick();
            });
        }
        tick();
    }

    // Speed test history: the earlier results, with a bar for each download
    // against what the connection can carry
    function speedHistory() {
        var all = (state && state.speedHistory) || [];
        if (!all.length) { return; }
        var a = state.adapter || {};
        var usb2 = a.bus === 'USB 2.0';
        var cap = usb2 ? 300 : Math.round((a.speed || 1000) * 0.94);
        var top = Math.max.apply(null, all.map(function (h) { return +h.downMbps || 0; }).concat([cap]));
        var rows = all.slice(0, 8).map(function (h) {
            var w = Math.max(2, Math.round((+h.downMbps || 0) / top * 100));
            return '<tr><td>' + esc(when(h.at)) + '</td><td class="barcell"><span class="bar"><i style="width:' + w + '%"></i></span><b>' + esc(String(h.downMbps)) + '</b></td><td>' +
                esc(String(h.upMbps)) + '</td><td>' + esc(h.pingMs !== null && h.pingMs !== undefined ? h.pingMs + ' ' + T('ms') : '') + '</td><td class="dim">' + esc(h.driver || '') + '</td></tr>';
        }).join('');
        overlay('message', T('Speed test history'),
            '<table class="speedhist"><tr class="head"><td>' + esc(T('When')) + '</td><td>' + esc(T('Download')) + '</td><td>' + esc(T('Upload')) + '</td><td>' + esc(T('Latency')) + '</td><td>' + esc(T('Driver')) + '</td></tr>' + rows + '</table>' +
            '<div class="speed-meta">' + esc(usb2 ? T('Speeds in Mbit/s.  The bars go up to {cap}, about the most a USB 2.0 adapter can carry.', { cap: top }) :
                T('Speeds in Mbit/s.  The bars go up to {cap}, about the most this link can carry.', { cap: top })) +
            '  ' + esc(T('A new driver or firmware shows up as a change in the driver column.')) + '</div>',
            T('Press OK or BACK to close.'));
    }

    // ------------------------------------------------------------------ actions

    function installArgs(extra) { return 'install -y ' + extra; }

    var actions = {
        boot: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled') {
                confirmThen(T('Stop running at boot?'), T('The adapter stays eth0 until the next reboot.  After that, the built-in port is eth0 again.'), function () {
                    act(T('Turn off at boot'), 'uninstall -y');
                });
            } else {
                confirmThen(T('Run at every boot?'), T('A small boot hook makes your USB adapter the TV\'s eth0 at every start, so the TV\'s settings show the wired connection and apps that refuse eth1 play.  It doesn\'t change any system files.  Turning it off puts the built-in port back as eth0 at the next reboot.'),
                    function () { act(T('Turn on at boot'), installArgs('')); });
            }
        },
        driver: function () {
            if (!state) { return; }
            var h = state.hook;
            if (state.driverOffer === 'none') { return; }
            // After a firmware update: the saved driver no longer fits, but one
            // is known for the new kernel, so switch to it
            if (state.driverOffer === 'replace') {
                var rpage = (state.driverPage || '').replace(/^https:\/\//, '');
                confirmThen(T('Switch to the driver for the new kernel?'),
                    T('A firmware update changed this TV\'s kernel{change}, so your faster driver isn\'t loaded anymore.  This downloads the one built for the new kernel{by}, checks its checksum, and uses it from now on.  The network drops for a moment while the adapter moves over.', {
                        change: state.kernelAtSetup ? T(' (from {old} to {new})', { old: state.kernelAtSetup, 'new': state.kernel }) : '',
                        by: rpage ? T(' by {who}', { who: rpage.split('/')[1] }) : ''
                    }),
                    function () {
                        act(T('Driver for the new kernel'), 'get-driver -y && sh ' + shq(SCRIPT) + ' ' + installArgs('--module ' + shq(state.driverFile)) +
                            ' && sh ' + shq(SCRIPT) + ' apply -y', null, true);
                    });
                return;
            }
            // A rebuild of the driver set up here is ready (like the ASIX
            // builds with Linux's 2022 RX fix)
            if (state.driverOffer === 'newer') {
                confirmThen(T('Get the fixed build of your driver?'),
                    T('A new build of the driver you use is ready: it doesn\'t count receive errors and drops that aren\'t real, and on a USB 2.0 port it downloads faster.  This downloads it, checks its checksum, and uses it from now on.  The network drops for a moment while the adapter moves over.'),
                    function () {
                        act(T('Fixed build of the driver'), 'get-driver -y && sh ' + shq(SCRIPT) + ' ' + installArgs('--module ' + shq(state.driverFile)) +
                            ' && sh ' + shq(SCRIPT) + ' apply -y', null, true);
                    });
                return;
            }
            if (h.module) {
                confirmThen(T('Stop using the faster driver?'), T('The boot hook stops loading it.  It stays in use until the next reboot.'), function () {
                    act(T('Faster driver off'), installArgs('--no-module'));
                });
            } else if (state.driverOffer === 'available') {
                var page = (state.driverPage || '').replace(/^https:\/\//, '');
                confirmThen(T('Use the faster driver?'),
                    T('This downloads a driver module built for this exact TV kernel{by}, checks its checksum, and loads it at every boot.  Moving the adapter to it takes the network down for a moment.  Wi-Fi is a good way back in if anything goes wrong.',
                        { by: page ? T(' by {who} ({page})', { who: page.split('/')[1], page: page }) : '' }),
                    function () {
                        act(T('Faster driver'), 'get-driver -y && sh ' + shq(SCRIPT) + ' ' + installArgs('--module ' + shq(state.driverFile)) +
                            ' && sh ' + shq(SCRIPT) + ' apply -y', null, true);
                    });
            }
        },
        drvtest: function () {
            if (!state || busy) { return; }
            var dt = state.driverTest || {};
            if (dt.state === 'running') { return; }
            if (dt.result) { drvtestResult(dt.available); } else { drvtestStart(); }
        },
        watch: function () {
            if (!state) { return; }
            var on = state.hook.state === 'enabled' && state.hook.watch;
            if (on) {
                confirmThen(T('Stop following plug and unplug?'), T('An adapter you plug in after boot stays as it is until you choose Switch now or reboot, and an adapter that stops answering is no longer restarted.'),
                    function () { act(T('Stop following plug and unplug'), installArgs('--no-watch')); });
            } else {
                confirmThen(T('Follow plug and unplug?'), T('After boot, it keeps checking every few seconds: an adapter you plug in becomes eth0, and when it\'s unplugged, the built-in port gets eth0 back.  It also restarts an adapter that stops answering.  It starts from the next boot.'),
                    function () { act(T('Follow plug and unplug'), installArgs('--watch')); });
            }
        },
        realtek: function () {
            if (!state) { return; }
            if (state.hook.realtekMode !== false) {
                confirmThen(T('Turn Realtek mode off?'),
                    T('Your Realtek adapter stays on the generic driver, which works but is slower.  It takes effect from the next boot.'),
                    function () { act(T('Realtek mode off'), installArgs('--no-realtek-mode')); });
            } else {
                confirmThen(T('Turn Realtek mode on?'), T('A Realtek RTL8152 or RTL8153 adapter left on the generic driver is switched to its Realtek mode, so the TV\'s own r8152 driver takes it, which is faster.  If r8152 doesn\'t take it within 5 seconds, it goes back to how it was.  It takes effect from the next boot.'),
                    function () { act(T('Realtek mode'), installArgs('--realtek-mode')); });
            }
        },
        wifi: function () {
            if (!state) { return; }
            var on = state.hook.state === 'enabled' && state.hook.wifiFallback;
            if (on) {
                confirmThen(T('Stop using Wi-Fi as a backup?'), T('If the cable stops working, the TV no longer turns Wi-Fi on by itself.  Wi-Fi stays as it is now.'),
                    function () { act(T('Wi-Fi backup off'), installArgs('--no-wifi-fallback')); });
            } else {
                var wakeOn = state.hook.state === 'enabled' && state.hook.wifiWake;
                confirmThen(T('Use Wi-Fi as a backup?'),
                    wakeOn ? T('You don\'t need this with Wi-Fi wake in standby on.  Wi-Fi wake keeps Wi-Fi connected, so if the cable stops working, the TV moves to Wi-Fi by itself.  This switch only acts when Wi-Fi is off: then it turns Wi-Fi on, and off again once the cable works.  It never turns off Wi-Fi it didn\'t turn on, so it won\'t touch Wi-Fi wake.') :
                        T('If eth0 loses its cable link for a minute while Wi-Fi is off, the TV turns Wi-Fi on and joins a network it already knows.  Once the cable works again, the Wi-Fi it turned on goes back off, so traffic returns to the adapter.  It never turns off Wi-Fi you had on.  Starts from the next boot.'),
                    function () { act(T('Wi-Fi backup'), installArgs('--wifi-fallback')); });
            }
        },
        wake: function () {
            if (!state) { return; }
            var on = state.hook.state === 'enabled' && state.hook.wifiWake;
            if (on) {
                confirmThen(T('Stop Wi-Fi wake in standby?'), T('The adapter stays connected in standby again, so on TVs that drop Wi-Fi then, Turn on via Wi-Fi may stop working.  It stops right away.'),
                    function () { act(T('Wi-Fi wake off'), installArgs('--no-wifi-wake')); });
            } else {
                confirmThen(T('Keep Wi-Fi wake in standby?'),
                    T('On some TVs, Turn on via Wi-Fi stops working in standby while the adapter is the main connection.  Just before standby, this disconnects only the adapter\'s network session (it stays plugged in), so Wi-Fi stays ready, and connects it again on wake.  Only when Wi-Fi is connected and Turn on via Wi-Fi is on.  Starts right away.'),
                    function () { act(T('Wi-Fi wake in standby'), installArgs('--wifi-wake')); });
            }
        },
        updates: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled' && state.hook.blockUpdates) {
                confirmThen(T('Stop blocking updates harder?'),
                    T('A firmware update can remove root for good.  webOS\'s update settings go back to how they were, and the extra servers and the firewall rule come off.  The Homebrew Channel\'s Block system updates stays as it is.'),
                    function () { act(T('Update blocking off'), installArgs('--no-block-updates')); });
            } else {
                confirmThen(T('Block updates harder?'),
                    T('A firmware update can remove root for good: LG\'s current firmware, webOS 26 from October 2026 on included, can\'t be rooted again.  It turns off webOS\'s update settings, blocks LG\'s update servers (the ones the Homebrew Channel\'s Block system updates covers, if that\'s off, and the ones it misses), and the one the updater reaches by IP.  It starts now, checks every 10 minutes that nothing undid it, and turning it off undoes all of it.  LG makes one check right after every restart, before anything on the TV can start: to stop that one too, block LG\'s update servers on your router (see the README).'),
                    function () { act(T('Block updates'), installArgs('--block-updates')); });
            }
        },
        phone: function () {
            if (!state) { return; }
            var h = state.hook, main = h.state === 'enabled' && h.blockUpdates;
            if ((state.updates || {}).phone === 'none') {
                overlay('message', T('Block phone app updates: not needed'),
                    esc(T('On other LG TVs, the TV\'s phone connection (what LG ThinQ and casting talk to) lists calls that let LG\'s phone app start a firmware update.  This TV\'s doesn\'t list any, so there\'s nothing to block here.  If a firmware update adds them, the block covers them from the next TV start, as long as Block updates harder is on.')),
                    T('Press OK or BACK to close.'));
                return;
            }
            if (main && h.blockPhone !== false) {
                confirmThen(T('Let phone apps start updates again?'),
                    T('From the next TV start, LG\'s phone app (LG ThinQ) can tell the TV to download and install a firmware update again, which can remove root for good.  The rest of the block stays on.'),
                    function () { act(T('Phone app updates allowed'), installArgs('--no-block-phone-updates')); });
            } else {
                confirmThen(T('Block phone app updates?'),
                    T('LG\'s phone app (LG ThinQ) can tell the TV to download and install a firmware update straight from the phone, which gets past every server block.  This makes the TV\'s phone connection stop offering that, from the next TV start, since it reads its list when the TV starts.  Casting, the phone remote and everything else keep working.  Turning it off puts it back from the next start.') +
                    (main ? '' : T('  It turns on Block updates harder too.')),
                    function () { act(T('Phone app updates blocked'), installArgs((main ? '' : '--block-updates ') + '--block-phone-updates')); });
            }
        },
        stopdl: function () {
            if (!state) { return; }
            var h = state.hook, main = h.state === 'enabled' && h.blockUpdates;
            if (main && h.stopDownloads !== false) {
                confirmThen(T('Turn off Stop firmware downloads?'),
                    T('A firmware download that gets past the block runs to the end again.  The rest of the block stays on.'),
                    function () { act(T('Stop firmware downloads off'), installArgs('--no-stop-downloads')); });
            } else {
                confirmThen(T('Stop firmware downloads?'),
                    T('A last line of defense, in case LG finds a way past the block: every 30 seconds while LG\'s updater is busy, this checks whether it\'s downloading firmware and cancels it, with a message on the TV.  It never stops an install that\'s already under way, or a USB update you started yourself.  It starts now.') +
                    (main ? '' : T('  It turns on Block updates harder too.')),
                    function () { act(T('Stop firmware downloads'), installArgs((main ? '' : '--block-updates ') + '--stop-downloads')); });
            }
        },
        remote: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled' && state.hook.blockRemoteSupport) {
                confirmThen(T('Allow LG Remote Support again?'), T('LG\'s support staff can connect to this TV again when you start a remote support session, and could push a firmware update during it.  Don\'t start a session with LG while the TV is rooted.'),
                    function () { act(T('Remote Support allowed'), installArgs('--no-block-remote-support')); });
            } else {
                confirmThen(T('Block LG Remote Support?'), T('Optional.  During an LG Remote Support session, LG\'s staff can push a firmware update straight to the TV, past the update check and the server blocks.  This blocks the remote support servers so that can\'t happen.  The catch: LG support can\'t connect to your TV while it\'s on, so turn it off first if you ever need them to.  It starts now and at every boot.'),
                    function () { act(T('Remote Support blocked'), installArgs('--block-remote-support')); });
            }
        },
        ipv6: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled' && state.hook.ipv6Off) {
                confirmThen(T('Turn IPv6 back on?'), T('IPv6 goes back to how it was.  If the speed test still says IPv6 is broken, connections wait about 200 ms again.'),
                    function () { act(T('IPv6 back on'), installArgs('--no-ipv6-off')); });
            } else {
                confirmThen(T('Turn off IPv6?'), T('Only for networks that give the TV IPv6 but don\'t carry it, where every app waits about 200 ms on each new connection (the speed test says when).  It turns IPv6 off on the TV, so everything uses IPv4, which every streaming app works over.  It starts now and at every boot, and turning it off puts IPv6 back.'),
                    function () { act(T('IPv6 off'), installArgs('--ipv6-off')); });
            }
        },
        eee: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled' && state.hook.eeeOff) {
                confirmThen(T('Leave Energy Efficient Ethernet on?'), T('The adapter goes back to its own setting the next time its link comes up.'),
                    function () { act(T('EEE back to default'), installArgs('--no-eee-off')); });
            } else {
                confirmThen(T('Turn off Energy Efficient Ethernet?'), T('Energy Efficient Ethernet lets the adapter and the router save a little power between packets.  On some adapters and routers it makes the link drop for a few seconds now and then.  This turns it off whenever the adapter\'s link comes up.  It uses ethtool, and not every driver allows it.'),
                    function () { act(T('EEE off'), installArgs('--eee-off')); });
            }
        },
        apply: function () {
            confirmThen(T('Switch now?'), T('The network drops for a few seconds while the adapter becomes eth0.'), function () {
                act(T('Switch now'), 'apply -y', null, true);
            });
        },
        // Upgrade from v1, as a walk-through: what's there, what changes,
        // then the upgrade and a check that it worked.  It runs the same
        // 'install' as the script, which replaces the v1 hook in place.
        upgrade: function () {
            if (!state || busy) { return; }
            var s = state, h = s.hook, wasOff = h.state === 'legacy-disabled';
            var hookDir = '/var/lib/webosbrew/init.d/';
            var found = wasOff ?
                li('warn', TC('A v1 boot hook you turned off is still in the boot folder, as {file}.  On many TVs that file still runs at every boot.', { file: hookDir + 'S01fix-eth.disabled' })) :
                li('warn', TC('The v1 boot hook is installed, at {file}.  It runs at every boot and renames {eth0} even when no adapter is plugged in.', { file: hookDir + 'S01fix-eth' }));
            var adapter = s.adapter && s.adapterIsEth0 ? li('ok', TC('Your USB adapter is {eth0} right now.')) :
                (s.adapter ? li('', TC('Your USB adapter is plugged in, as {name}.', { name: s.adapter.name })) : li('', esc(T('No USB adapter is plugged in right now.'))));
            stepThen(T('Upgrade from v1'), '<span class="step-of">' + esc(T('Step 1 of 3 · what\'s there now')) + '</span><ul class="walk">' + found + adapter +
                li('', esc(T('The upgrade takes a few seconds and doesn\'t touch the network.'))) + '</ul>',
                T('Press OK to see what changes, or BACK to cancel.'), function () {
                    stepThen(T('Upgrade from v1'), '<span class="step-of">' + esc(T('Step 2 of 3 · what changes')) + '</span><ul class="walk">' +
                        li('ok', esc(T('The v1 hook is replaced, in place, by this version\'s: a link to the script inside this app, so updating the app updates the hook too.'))) +
                        li('ok', esc(T('Nothing switches now.  The adapter stays as it is until the next boot.'))) +
                        li('ok', esc(T('At boot, the new hook only changes anything when an adapter is plugged in, and puts the old names back if a step fails.'))) +
                        li('', esc(T('It starts with the defaults.  Turn on Faster driver, Follow plug and unplug or Wi-Fi as a backup afterwards if you want them.'))) +
                        li('', esc(wasOff ? T('This turns the boot hook on.  Prefer it off?  Turn off Run at every boot afterwards.') : T('To undo everything later, use Turn everything off.'))) + '</ul>',
                        T('Press OK to upgrade, or BACK to cancel.'), upgradeNow);
                });
        },
        update: function () {
            if (!upd || !upd.newer || busy) { return; }
            var latest = upd.latest, homebrew = upd.source === 'homebrew';
            busy = true;
            overlay('busy', T('Update to v{v}?', { v: latest }), '<span class="spinner"></span>' + esc(T('Checking what\'s new…')), '');
            fetchChanges(state ? state.version : '0', latest, function (secs) {
                busy = false;
                var news = secs ? '<p>' + esc(T('What\'s new since v{v}:', { v: state ? state.version : '' })) + '</p>' + wnList(secs, 8) : '';
                if (homebrew) {
                    stepThen(T('Update to v{v}?', { v: latest }), news + '<p>' + esc(T('Installed from the Homebrew Channel, so it updates there.  OK opens the Homebrew Channel.')) + '</p>',
                        T('Press OK to go ahead, or BACK to cancel.'), function () {
                            closeOverlay();
                            luna('luna://com.webos.applicationManager/launch', { id: 'org.webosbrew.hbchannel' }, function () {});
                        });
                    return;
                }
                stepThen(T('Update to v{v}?', { v: latest }), news + '<p>' +
                    esc(T('Downloads the new version from GitHub, checks its SHA-256, and installs it.  The app closes and opens again by itself.  Your settings stay as they are.')) + '</p>',
                    T('Press OK to go ahead, or BACK to cancel.'), function () {
                    closeOverlay();
                    act(T('Update'), 'update -y', function (ok, text) {
                        // What's new shows once the new version opens, not here
                        if (ok && /Installing/.test(text || '')) {
                            overlay('message', T('Updating to v{v}', { v: upd.latest }),
                                '<span class="spinner"></span>' + esc(T('Checked the download and installing it now.  The app closes and opens again by itself in a few seconds, then shows what\'s new.')), '');
                        }
                    });
                });
            });
        },
        speed: function () {
            if (busy) { return; }
            busy = true;
            var r = { pingMs: null, downMbps: null, upMbps: null, server: '', provider: '', interface: '', moved: false, ipv6Broken: false, at: null };
            function tile(label, value, unit, running) {
                return '<div class="tile' + (running ? ' run' : '') + '"><small>' + label + '</small>' +
                    (value === null ? '<b class="wait">' + (running ? '…' : '–') + '</b>' : '<b>' + esc(String(value)) + '</b>') +
                    '<span>' + unit + '</span></div>';
            }
            // Earlier results, with the driver each ran on, so a firmware or
            // driver change shows in the numbers.  This run is left out by its
            // start time, so a limited run (not saved) doesn't hide an older one.
            function history(s) {
                var all = (s && s.speedHistory) || [], h = [];
                for (var j = 0; j < all.length && h.length < 4; j++) {
                    if (!(r.at && all[j].at === r.at)) { h.push(all[j]); }
                }
                if (!h.length) { return ''; }
                var rows = '';
                for (var i = 0; i < h.length; i++) {
                    var d = h[i].at ? new Date(h[i].at * 1000) : null;
                    rows += '<tr><td>' + esc(d ? d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '') +
                        '</td><td>' + esc((h[i].downMbps || '?') + ' / ' + (h[i].upMbps || '?')) + '</td><td>' + esc(h[i].driver || '') +
                        '</td><td>' + esc((h[i].server || '').split(',')[0]) + '</td></tr>';
                }
                return '<div class="speed-meta">' + esc(T('Earlier (down / up Mbit/s, driver, server):')) + '</div><table class="hist">' + rows + '</table>';
            }
            function draw(stage, done, s) {
                var where = r.interface ? (r.server ? T('Over {nic}, to {server}.', { nic: r.interface, server: r.server }) : T('Over {nic}.', { nic: r.interface })) : T('Finding a server…');
                overlay(done ? 'message' : 'busy', done ? T('Speed test') : T('Speed test: {stage}', { stage: T(stage) }),
                    '<div class="speed">' + tile(esc(T('Download')), r.downMbps, esc(T('Mbit/s')), stage === 'download') +
                    tile(esc(T('Upload')), r.upMbps, esc(T('Mbit/s')), stage === 'upload') + tile(esc(T('Latency')), r.pingMs, esc(T('ms')), stage === 'latency') +
                    '</div><div class="speed-meta">' + esc(where + T('  Uses a few hundred MB of data.')) + '</div>' +
                    (r.ipv6Broken ? '<div class="speed-meta warn">' + esc(T('IPv6 is broken on your network: the TV tries it first, gets nothing back, and every app waits about 200 ms before it uses IPv4.  This test used IPv4.  Fix IPv6 on your router, or turn on Turn off IPv6 below.')) + '</div>' : '') +
                    (r.provider === 'librespeed' && !r.moved && r.server ? '<div class="speed-meta warn">' + esc(T('{server} is a backup server, and usually measures lower than Cloudflare.  For your real speed, choose Auto in Speed test server.', { server: r.server })) + '</div>' : '') +
                    (r.moved ? '<div class="speed-meta warn">' + esc(T('Cloudflare looks blocked or throttled on your network, so Auto used the closest other server.  Speed test server picks a different one.')) + '</div>' : '') +
                    (r.limited ? '<div class="speed-meta warn">' + esc(T('Cloudflare limited this test (too many speed tests from your network in a row), so these numbers are too low.  Try again in 10 to 15 minutes.')) + '</div>' : '') + (done ? history(s) : ''),
                    done ? T('Press OK or BACK to close.') : T('This takes about 15 seconds.'));
            }
            function fail(text) {
                busy = false;
                overlay('message', T('Speed test: something went wrong'),
                    '<pre>' + esc((text || T('No answer from the script.')).replace(/\x1b\[[0-9;]*m/g, '').trim()) + '</pre>', T('Press OK or BACK to close.'));
                refresh();
            }
            function step(phase, stage, next) {
                draw(stage, false);
                runScript('speedtest --json --phase ' + phase, function (ok, out, err) {
                    var d = null;
                    try { d = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { d = null; }
                    if (!d) { fail(out || err); return; }
                    for (var k in d) { if (d[k] !== null && d[k] !== '') { r[k] = d[k]; } }
                    next();
                });
            }
            step('ping', 'latency', function () {
                step('down', 'download', function () {
                    step('up', 'upload', function () {
                        busy = false;
                        // The earlier results are already here from when the
                        // app opened, so they show right away.  The refresh
                        // behind it updates the main screen and the list.
                        draw('', true, state);
                        refresh(function (s) { if (overlayMode === 'message' && s) { draw('', true, s); } });
                    });
                });
            });
        },
        // Speed test server: a list, closest first, measured when it opens
        speedsrv: function () {
            if (busy) { return; }
            busy = true;
            overlay('busy', T('Speed test server'), '<span class="spinner"></span>' + esc(T('Checking how far each server is…')), '');
            runScript('speed-server --json', function (ok, out, err) {
                busy = false;
                var d = null;
                try { d = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { d = null; }
                if (!d || !d.servers) { pickFailed(out || err); return; }
                var items = [
                    { id: 'auto', name: T('Auto (recommended)'), sub: T('Cloudflare, or the closest server below where Cloudflare is blocked') },
                    { id: 'cloudflare', name: 'Cloudflare', bad: !d.cloudflare.ok,
                        sub: d.cloudflare.ok ? T('The fastest.  Its nearest city: {city}', { city: d.cloudflare.city || '?' }) : T('Blocked or throttled on your network') }
                ];
                var list = d.servers.slice().sort(function (a, b) {
                    if ((a.pingMs === null) !== (b.pingMs === null)) { return a.pingMs === null ? 1 : -1; }
                    return (a.pingMs || 0) - (b.pingMs || 0) || (a.name < b.name ? -1 : 1);
                });
                var mine = d.choice !== 'auto' && d.choice !== 'cloudflare';
                // Each backup server's last result here, so the slow ones show
                var hist = (state && state.speedHistory) || [], last = {};
                for (var h = hist.length - 1; h >= 0; h--) { if (hist[h].server) { last[hist[h].server] = hist[h]; } }
                for (var i = 0; i < list.length; i++) {
                    if (list[i].url === d.choice) { mine = false; }
                    var l = last[list[i].name];
                    items.push({ id: list[i].url, name: list[i].name, ms: list[i].pingMs, bad: list[i].pingMs === null,
                        sub: list[i].pingMs === null ? T('No answer right now') :
                            (l ? T('Backup.  Last test here: {down} / {up} Mbit/s', { down: l.downMbps, up: l.upMbps }) : T('Backup, usually slower than Cloudflare')) });
                }
                // Your own server, chosen over SSH
                if (mine) { items.push({ id: d.choice, name: d.name, sub: T('Your own server') }); }
                pick(items, d.choice, T('Cloudflare is the fastest by far, and Auto uses it.  The other servers are only a backup for networks where Cloudflare is blocked, like in Russia.  Most are small volunteer servers and measure well below your real speed.'));
            });
        },
        netcheck: netCheck,
        netinfo: netInfo,
        traffic: liveTraffic,
        health: linkHealth,
        speedhist: speedHistory,
        report: function () {
            runScript('report', function (ok, out) {
                // The issue form adds its own code block, so drop the fences.  Squeeze
                // runs of spaces so the QR code stays easy to scan.
                var report = (out || '').replace(/\x1b\[[0-9;]*m/g, '').replace(/^```\s*$/mg, '')
                    .replace(/ {2,}/g, ' ').trim();
                var s = state || { model: '', webos: '', webosRelease: '', firmware: '', adapter: null };
                var a = s.adapter;
                var adapter = a ? ((a.chip || 'USB adapter') + (a.id ? ' (' + a.id + ')' : '')) : '';
                // The form has its own fields for the model and webOS, so the report
                // field skips those lines.  Shorter URL, easier QR code.
                var short = report.split('\n').filter(function (l) { return !/^(Model|webOS):/.test(l); }).join('\n');
                var form = REPO_PATH + '/issues/new?template=compatibility-report.yml' +
                    '&title=' + q('[Compat] ' + (s.model || 'LG TV') + ' + ' + (a ? (a.chip || a.id) : 'adapter')) +
                    '&model=' + q(s.model || '') +
                    '&webos=' + q((s.webos || '') + ' (' + (s.webosRelease || '') + '), firmware ' + (s.firmware || '')) +
                    '&adapter=' + q(adapter) +
                    (s.speed && s.speed.downMbps ? '&speed=' + q(s.speed.downMbps + ' down / ' + (s.speed.upMbps || '?') +
                        ' up Mbit/s with the app\'s speed test' + (a && a.bus ? ' (' + a.bus + ')' : '')) : '') +
                    '&result=' + q(guessResult(s)) +
                    (usedOptions(s) ? '&options=' + q(usedOptions(s)) : '') +
                    '&report=' + q(short);
                // The GitHub phone apps grab github.com/<owner>/<repo> links and open
                // a blank issue, dropping the filled-in fields.  They leave /login
                // alone, so the phone's browser opens it, and GitHub then forwards to
                // the form (straight away if you're already signed in).
                var url = 'https://github.com/login?return_to=' + encodeURIComponent(form);
                var svg = '';
                try {
                    var qr = window.qrcode(0, 'L');
                    qr.addData(url);
                    qr.make();
                    svg = qr.createSvgTag({ cellSize: 4, margin: 16, scalable: true });
                } catch (e) {
                    svg = '';
                }
                overlay('message', T('Report for GitHub'),
                    '<div class="qr">' + svg + '<div>' + esc(T('Scan this with your phone to open a compatibility report on GitHub, already filled in.  It opens in your browser so the details carry over.  Check the result it picked and submit.  MAC addresses are hidden.')) +
                    '<br><br><pre>' + esc(report.split('\n').slice(0, 12).join('\n')) + '</pre></div></div>',
                    T('Press OK or BACK to close.'));
            });
        },
        off: function () {
            confirmThen(T('Turn everything off?'), T('This removes the boot hook, gives eth0 back to the built-in port now, undoes every switch (the update blocks included) and deletes everything it kept on the TV: settings, log, history and downloaded drivers.  Removing the app does the same within about a minute, but this is quicker.'), function () {
                act(T('Turn everything off'), 'uninstall -y --now', null, true);
            });
        },
        // Who made it and under which licenses, with a QR code for the full texts
        whatsnew: function () {
            var v = state ? state.version : (window.LGU2E_WHATSNEW && window.LGU2E_WHATSNEW.version);
            if (!showWhatsNew(T('What\'s new in v{v}', { v: v || '' }))) {
                overlay('message', T('What\'s new'), esc(T('This build has no notes.  See github.com/ohmybahgosh/LG-USB-2-ETH0/releases')), T('Press OK or BACK to close.'));
            }
        },
        about: function () {
            var qr = '';
            try {
                var q = window.qrcode(0, 'L');
                q.addData(REPO + '#license');
                q.make();
                qr = q.createSvgTag({ cellSize: 4, margin: 16, scalable: true });
            } catch (e) { qr = ''; }
            var v = state && state.version ? state.version : '';
            overlay('message', T('About and licenses'),
                '<div class="qr qr-setup">' + qr + '<div class="about">' +
                '<p>' + esc(T('LG-USB-2-ETH0 {v} by OhMyBahGosh.  Free and open source under the MIT License.', { v: v ? 'v' + v : '' })) + '</p>' +
                '<p>' + esc(T('It includes qrcode-generator by Kazuhiko Arase, also under the MIT License.')) + '</p>' +
                '<p>' + esc(T('The driver modules Faster driver downloads are GPL-2.0, like the Linux drivers they come from.  Where each one\'s source is: github.com/ohmybahgosh/lg-webos-usb-drivers')) + '</p>' +
                '<p>' + esc(T('The full license texts come with the app (LICENSE and vendor/qrcode.LICENSE.txt), and the code opens them on GitHub.')) + '</p>' +
                '<p>' + esc(T('Not affiliated with LG Electronics.')) + '</p>' +
                '</div></div>',
                T('Press OK or BACK to close.'));
        },
        // Language: Auto (the TV's menu language), then each language in turn.
        // The page reloads in the new one; the choice stays in the app's storage.
        lang: function () {
            if (busy || !I18N) { return; }
            if (I18N.next()) {
                try { window.sessionStorage.setItem('lgu2e.focus', 'lang'); } catch (e) { /* not kept */ }
                window.location.reload();
            }
        }
    };

    // ------------------------------------------------------------------ remote / keyboard

    // Only the open tab's buttons on screen, in order (hidden rows are skipped)
    function buttons() { return tabRows(tab); }
    var current = 0;
    function focusCurrent() {
        // On the tab bar the open tab's rows still get laid out (and the
        // scroll rail updated), only the focus goes to the tab
        var tabEl = onTabs ? document.querySelector('.tab[data-tab="' + tab + '"]') : null;
        if (onTabs && !tabEl) { onTabs = false; }
        var list = buttons();
        if (!list.length) {
            $('rail').className = 'rail';
            if (tabEl) { tabEl.focus(); }
            return;
        }
        if (current >= list.length) { current = list.length - 1; }
        // Scroll the rows so the focused one shows whole, starting the view at
        // a row's top edge (never half a row at the top)
        var box = $('rows'), first = 0, used = 0;
        for (var i = current; i >= 0; i--) {
            used += list[i].offsetHeight + 14;
            if (used - 14 > box.clientHeight) { break; }
            first = i;
        }
        box.scrollTop = first > 0 ? list[first].offsetTop - list[0].offsetTop : 0;
        // A row that doesn't fit whole is hidden, not cut off, and arrows say
        // there's more above or below (TVs draw text a little taller than a PC)
        var top = box.scrollTop, bottom = top + box.clientHeight, above = false, below = false;
        var shown = 0, firstShown = -1;
        for (var j = 0; j < list.length; j++) {
            var rt = list[j].offsetTop - list[0].offsetTop, rb = rt + list[j].offsetHeight;
            var whole = rt >= top - 1 && rb <= bottom + 1;
            list[j].style.visibility = whole ? '' : 'hidden';
            if (whole) { shown++; if (firstShown < 0) { firstShown = j; } }
            if (!whole && rb <= top + 1) { above = true; }
            if (!whole && rt >= top) { below = true; }
        }
        // The rail sits beside the rows: thumb size is the share of rows on
        // screen, its place is where they are in the list
        var rail = $('rail'), more = above || below;
        rail.className = 'rail' + (more ? ' show' : '');
        if (more) {
            var last = list[firstShown + shown - 1];
            var h = last.offsetTop - list[0].offsetTop + last.offsetHeight - top;
            rail.style.top = (box.offsetTop + 22) + 'px';
            rail.style.height = Math.max(h - 44, 60) + 'px';
            var track = rail.clientHeight;
            $('rail-thumb').style.height = Math.max(track * shown / list.length, 24) + 'px';
            $('rail-thumb').style.top = (track * firstShown / list.length) + 'px';
            rail.children[0].className = 'rail-cap up' + (above ? ' lit' : '');
            rail.children[2].className = 'rail-cap down' + (below ? ' lit' : '');
        }
        if (tabEl) { tabEl.focus(); } else { list[current].focus({ preventScroll: true }); }
    }

    function exitApp() {
        if (window.PalmSystem && window.PalmSystem.platformBack) { window.PalmSystem.platformBack(); }
        else { window.close(); }
    }

    document.addEventListener('keydown', function (e) {
        var k = e.keyCode;
        if (overlayMode) {
            if (overlayMode === 'busy') { e.preventDefault(); return; }
            if (overlayMode === 'setup') {
                if (k === KEY.ENTER) { refresh(); }
                else if (k === KEY.BACK || k === KEY.ESC) { exitApp(); }
                e.preventDefault();
                return;
            }
            if (overlayMode === 'pick') {
                if (k === KEY.DOWN) { pickAt = Math.min(pickAt + 1, pickItems.length - 1); pickFocus(); }
                else if (k === KEY.UP) { pickAt = Math.max(pickAt - 1, 0); pickFocus(); }
                else if (k === KEY.ENTER) { pickChoose(); }
                else if (k === KEY.BACK || k === KEY.ESC || k === KEY.BACKSPACE) { closeOverlay(); }
                e.preventDefault();
                return;
            }
            if (overlayMode === 'message' && Date.now() < wnGuardUntil) { e.preventDefault(); return; }
            if (k === KEY.ENTER && overlayMode === 'confirm' && onConfirm) {
                var fn = onConfirm;
                onConfirm = null;
                fn();
            } else if (k === KEY.ENTER || k === KEY.BACK || k === KEY.ESC || k === KEY.BACKSPACE) {
                closeOverlay();
            }
            e.preventDefault();
            return;
        }
        var list = buttons();
        // Up on the tab bar: LEFT and RIGHT pick a tab, DOWN or OK go into it
        if (onTabs) {
            if (k === KEY.LEFT) { stepTab(-1); }
            else if (k === KEY.RIGHT) { stepTab(1); }
            else if (k === KEY.DOWN || k === KEY.ENTER) { onTabs = false; current = 0; focusCurrent(); }
            else if (k === KEY.BACK || k === KEY.ESC) { exitApp(); }
            e.preventDefault();
            return;
        }
        if (k === KEY.DOWN) { current = Math.min(current + 1, list.length - 1); focusCurrent(); e.preventDefault(); }
        else if (k === KEY.UP && current === 0) { onTabs = true; focusCurrent(); e.preventDefault(); }
        else if (k === KEY.UP) { current = Math.max(current - 1, 0); focusCurrent(); e.preventDefault(); }
        else if (k === KEY.LEFT) { stepTab(-1); e.preventDefault(); }
        else if (k === KEY.RIGHT) { stepTab(1); e.preventDefault(); }
        else if (k === KEY.ENTER) {
            var btn = list[current];
            if (btn && btn.className.indexOf('disabled') < 0) { actions[btn.getAttribute('data-action')](); }
            e.preventDefault();
        } else if (k === KEY.BACK || k === KEY.ESC) { exitApp(); e.preventDefault(); }
    });

    // Magic Remote pointer: hovering moves focus, clicking acts
    Array.prototype.slice.call(document.querySelectorAll('.btn')).forEach(function (btn) {
        btn.addEventListener('mouseover', function () { onTabs = false; current = buttons().indexOf(btn); focusCurrent(); });
        btn.addEventListener('click', function () {
            current = buttons().indexOf(btn);
            if (!overlayMode && btn.className.indexOf('disabled') < 0) { actions[btn.getAttribute('data-action')](); }
        });
    });
    // Magic Remote pointer on the tabs
    Array.prototype.slice.call(document.querySelectorAll('.tab')).forEach(function (el) {
        el.addEventListener('click', function () { if (!overlayMode) { onTabs = true; openTab(el.getAttribute('data-tab')); } });
    });
    $('overlay').addEventListener('click', function () {
        if (overlayMode === 'confirm' && onConfirm) { var fn = onConfirm; onConfirm = null; fn(); }
        else if (overlayMode === 'message' && Date.now() >= wnGuardUntil) { closeOverlay(); }
    });

    // Refresh when the app comes back to the foreground
    document.addEventListener('webOSRelaunch', refresh);
    document.addEventListener('visibilitychange', function () { if (!document.hidden && !busy) { refresh(); } });

    // And now and then while it's open, so plugging or unplugging shows up
    setInterval(function () { if (!document.hidden && !busy && !waitTimer) { refresh(); } }, 30000);

    if (I18N) { I18N.translatePage(document.body); }
    $('lang-hint').textContent = I18N ? I18N.label() : 'English';
    // Back on the Language row after switching
    try {
        if (window.sessionStorage.getItem('lgu2e.focus') === 'lang') {
            window.sessionStorage.removeItem('lgu2e.focus');
            tab = 'more';
            fitRows();
            current = buttons().indexOf(document.querySelector('[data-action="lang"]'));
        }
    } catch (e) { /* first row */ }
    fitRows();
    focusCurrent();
    tvInfo(function () { refresh(function (s) { whatsNew(s); drvtestOffer(s); }); });
    checkUpdate();
}());
