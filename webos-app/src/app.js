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
    var overlayMode = null; // null, 'busy', 'message', 'confirm'
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

    // Run the bundled script as root. cb(ok, stdout, stderr)
    function runScript(args, cb) {
        if (window.LGU2E_DEMO) { window.LGU2E_DEMO(args, cb); return; }
        luna(HBC_EXEC, { command: 'sh ' + shq(SCRIPT) + ' ' + args + ' 2>&1' }, function (r) {
            cb(r.returnValue !== false, r.stdoutString || '', r.errorText || r.stderrString || '');
        });
    }

    // ------------------------------------------------------------------ status

    function refresh(cb) {
        runScript('status --json', function (ok, out, err) {
            var data = null;
            try { data = JSON.parse(out.slice(out.indexOf('{'))); } catch (e) { data = null; }
            if (!data) {
                showNoRoot(ok ? 'The script gave an unexpected answer.' : err);
                if (cb) { cb(null); }
                return;
            }
            state = data;
            render();
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
                    hint('eth0 is connected at ' + e.ip.replace(/\/\d+$/, '') + '.  Press OK or BACK to close.');
                } else if (++tries < 20) {
                    hint('Waiting for eth0 to get an address…  Press OK or BACK to close.');
                    waitTimer = setTimeout(check, 2000);
                } else {
                    hint('eth0 has no address after 40 seconds.  Check the cable and the router.  Press OK or BACK to close.');
                }
            });
        }
        check();
    }

    function showNoRoot(detail) {
        $('dot').className = 'dot dot-bad';
        $('headline').textContent = "Can't reach the TV as root";
        $('subline').textContent = 'This app needs a rooted TV with the Homebrew Channel.  ' + (detail || '');
        $('facts').innerHTML = '';
        $('notes').innerHTML = '';
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
            head = 'USB adapter is eth0';
            sub = s.defaultRoute === 'eth0' ? 'Traffic is going over the adapter.' : 'Traffic is going out ' + (s.defaultRoute || 'nowhere') + ', not the adapter.';
            if (s.defaultRoute !== 'eth0') { dot = 'dot-warn'; }
        } else if (a) {
            head = 'Adapter found, not eth0 yet';
            sub = h.state === 'enabled' ? 'Choose Switch now, or reboot.' : 'Turn on Run at every boot, or choose Switch now.';
            dot = 'dot-warn';
        } else {
            head = 'No USB adapter found';
            sub = 'Plug in a USB Ethernet adapter.  The built-in port keeps working meanwhile.';
            dot = 'dot-warn';
        }
        if (s.issues.length) { dot = 'dot-bad'; sub = s.issues[0]; }
        else if (dot === 'dot-ok') { sub += '  No problems found.'; }
        $('dot').className = 'dot ' + dot;
        $('headline').textContent = head;
        $('subline').textContent = sub;

        // Facts
        var html = '';
        if (a) {
            html += row('Adapter', esc((a.chip || a.id || 'USB') + ' · ' + a.driver) +
                (a.driver === h.driver && h.driver ? ' <span class="ok">✔</span>' : ''));
            html += row('Link', esc((a.speed ? a.speed + ' Mbit/s' : (a.carrier ? 'up' : 'no cable')) + (a.bus ? ' · ' + a.bus : '')));
            html += row('Address', esc(a.ip ? a.ip.replace(/\/\d+$/, '') : 'none yet'));
        } else {
            html += row('Adapter', 'none');
        }
        if (b) { html += row('Built-in port', esc(b.name + ' · ' + (b.carrier ? 'cable in' : 'no cable'))); }
        if (w) { html += row('Wi-Fi', w.carrier ? '<span class="warn">connected</span>' : 'off'); }
        var hookText = { enabled: 'on', disabled: 'off (disabled)', none: 'off', broken: 'broken link', legacy: 'old v1 hook', 'legacy-disabled': 'old v1 hook' }[h.state] || h.state;
        html += row('At boot', esc(hookText + (h.running ? ' · running' : '')));
        var last = s.log.length ? s.log[s.log.length - 1] : '';
        if (last) { html += row('Last log', esc(last)); }
        $('facts').innerHTML = html;

        // Notes (skip the first issue, already in the subline)
        var notes = s.issues.slice(1).concat(s.notes).slice(0, 4);
        $('notes').innerHTML = notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('');

        // Toggles
        var bootOn = h.state === 'enabled';
        $('tog-boot').className = 'tog' + (bootOn ? ' on' : '');
        $('tog-watch').className = 'tog' + (bootOn && h.watch ? ' on' : '');
        // The faster-driver row only appears when it fits this TV: a driver is
        // known for this exact kernel and the adapter is a Realtek one, or a
        // driver is already set up (so it can be turned off again).
        var offer = s.driverOffer || 'none';
        var driverBtn = document.querySelector('[data-action="driver"]');
        var hints = {
            available: 'built for this TV\'s kernel',
            active: h.driver || 'custom module',
            'wrong-kernel': 'built for an older kernel, not loaded',
            changed: 'file changed, not loaded',
            missing: 'module file is missing'
        };
        driverBtn.style.display = offer === 'none' ? 'none' : '';
        $('driver-hint').textContent = hints[offer] || '';
        $('tog-driver').className = 'tog' + (offer !== 'none' && offer !== 'available' && bootOn ? ' on' : '');
        if (current >= buttons().length) { current = buttons().length - 1; }
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
        onConfirm = null;
        $('overlay').className = 'overlay hidden';
        focusCurrent();
    }

    // Run a script command with a busy screen, then show its output
    function act(title, args, after, network) {
        if (busy) { return; }
        busy = true;
        overlay('busy', title, '<span class="spinner"></span>Working on it…  The picture is fine, only the network is changing.', '');
        runScript(args, function (ok, out, err) {
            busy = false;
            var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim();
            var lines = text.split('\n');
            if (lines.length > 14) { lines = lines.slice(lines.length - 14); }
            overlay('message', ok ? title + ': done' : title + ': something went wrong',
                '<pre>' + esc(lines.join('\n')) + '</pre>', 'Press OK or BACK to close.');
            if (network && ok) { waitForAddress(); } else { refresh(); }
            if (after) { after(ok); }
        });
    }

    function confirmThen(title, text, fn) {
        onConfirm = fn;
        overlay('confirm', title, esc(text), 'Press OK to go ahead, or BACK to cancel.');
    }

    // ------------------------------------------------------------------ actions

    function installArgs(extra) { return 'install -y ' + extra; }

    var actions = {
        boot: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled') {
                confirmThen('Stop running at boot?', 'The adapter stays eth0 until the next reboot.  After that, the built-in port is eth0 again.', function () {
                    act('Turn off at boot', 'uninstall -y');
                });
            } else {
                act('Turn on at boot', installArgs(''));
            }
        },
        driver: function () {
            if (!state) { return; }
            var h = state.hook;
            if (state.driverOffer === 'none') { return; }
            if (h.module) {
                confirmThen('Stop using the faster driver?', 'The boot hook stops loading it.  It stays in use until the next reboot.', function () {
                    act('Faster driver off', installArgs('--no-module'));
                });
            } else if (state.driverOffer === 'available') {
                confirmThen('Use the faster Realtek driver?',
                    'This downloads a driver module built for this exact TV kernel by DonZoomik (github.com/DonZoomik/webos-r8152), checks its checksum, and loads it at every boot.  ' +
                    'Moving the adapter to it takes the network down for a moment.  Wi-Fi is a good way back in if anything goes wrong.',
                    function () {
                        act('Faster driver', 'get-driver -y && sh ' + shq(SCRIPT) + ' ' + installArgs('--module ' + shq(state.driverFile)) +
                            ' && sh ' + shq(SCRIPT) + ' apply -y', null, true);
                    });
            }
        },
        watch: function () {
            if (!state) { return; }
            var on = state.hook.state === 'enabled' && state.hook.watch;
            act(on ? 'Stop following plug and unplug' : 'Follow plug and unplug', installArgs(on ? '--no-watch' : '--watch'));
        },
        apply: function () {
            confirmThen('Switch now?', 'The network drops for a few seconds while the adapter becomes eth0.', function () {
                act('Switch now', 'apply -y', null, true);
            });
        },
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
                overlay('message', 'Report for GitHub',
                    '<div class="qr">' + svg + '<div>Scan this with your phone to open a compatibility report on GitHub, already filled in.  ' +
                    'It opens in your browser so the details carry over.  Check the result it picked and submit.  MAC addresses are hidden.<br><br><pre>' + esc(report.split('\n').slice(0, 12).join('\n')) + '</pre></div></div>',
                    'Press OK or BACK to close.');
            });
        },
        off: function () {
            confirmThen('Turn everything off?', 'This removes the boot hook and gives eth0 back to the built-in port now.  Do this before removing the app.', function () {
                act('Turn everything off', 'uninstall -y --now', null, true);
            });
        }
    };

    // ------------------------------------------------------------------ remote / keyboard

    // Only the buttons on screen, in order (hidden rows are skipped)
    function buttons() {
        return Array.prototype.slice.call(document.querySelectorAll('.btn')).filter(function (b) {
            return b.style.display !== 'none';
        });
    }
    var current = 0;
    function focusCurrent() {
        var list = buttons();
        if (!list.length) { return; }
        if (current >= list.length) { current = list.length - 1; }
        list[current].focus();
    }

    function exitApp() {
        if (window.PalmSystem && window.PalmSystem.platformBack) { window.PalmSystem.platformBack(); }
        else { window.close(); }
    }

    document.addEventListener('keydown', function (e) {
        var k = e.keyCode;
        if (overlayMode) {
            if (overlayMode === 'busy') { e.preventDefault(); return; }
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
        if (k === KEY.DOWN) { current = Math.min(current + 1, list.length - 1); focusCurrent(); e.preventDefault(); }
        else if (k === KEY.UP) { current = Math.max(current - 1, 0); focusCurrent(); e.preventDefault(); }
        else if (k === KEY.ENTER) {
            var btn = list[current];
            if (btn && btn.className.indexOf('disabled') < 0) { actions[btn.getAttribute('data-action')](); }
            e.preventDefault();
        } else if (k === KEY.BACK || k === KEY.ESC) { exitApp(); e.preventDefault(); }
    });

    // Magic Remote pointer: hovering moves focus, clicking acts
    Array.prototype.slice.call(document.querySelectorAll('.btn')).forEach(function (btn) {
        btn.addEventListener('mouseover', function () { current = buttons().indexOf(btn); focusCurrent(); });
        btn.addEventListener('click', function () {
            current = buttons().indexOf(btn);
            if (!overlayMode && btn.className.indexOf('disabled') < 0) { actions[btn.getAttribute('data-action')](); }
        });
    });
    $('overlay').addEventListener('click', function () {
        if (overlayMode === 'confirm' && onConfirm) { var fn = onConfirm; onConfirm = null; fn(); }
        else if (overlayMode === 'message') { closeOverlay(); }
    });

    // Refresh when the app comes back to the foreground
    document.addEventListener('webOSRelaunch', refresh);
    document.addEventListener('visibilitychange', function () { if (!document.hidden && !busy) { refresh(); } });

    // And now and then while it's open, so plugging or unplugging shows up
    setInterval(function () { if (!document.hidden && !busy && !waitTimer) { refresh(); } }, 30000);

    focusCurrent();
    refresh();
}());
