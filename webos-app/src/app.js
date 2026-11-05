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
    var upd = null;        // last update --check --json result
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
        if (h.wifiFallback) { o.push('--wifi-fallback'); }
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
        // The script's v1 advice is for SSH ("Run 'install'").  In the app,
        // point at the Upgrade from v1 row instead.
        var v1 = h.state === 'legacy' || h.state === 'legacy-disabled';
        var issues = s.issues.map(function (i) {
            return v1 && /'install'/.test(i) ? 'An old v1 boot hook is installed.  Choose Upgrade from v1 to replace it, step by step.' : i;
        });
        if (issues.length) { dot = 'dot-bad'; sub = issues[0]; }
        else if (dot === 'dot-ok') { sub += '  No problems found.'; }
        $('dot').className = 'dot ' + dot;
        $('headline').textContent = head;
        $('subline').textContent = sub;

        // Facts
        var html = '';
        if (a) {
            html += row('Adapter', esc((a.chip || a.id || 'USB') + ' · ' + a.driver) +
                (a.driver === h.driver && h.driver ? ' <span class="ok">✔</span>' : ''));
            // A gigabit adapter on a 100 Mbit/s link (a two-pair cable, a slow
            // router port) or a half-duplex one is worth pointing out
            var slow = a.carrier && ((a.speed && a.speed < 1000) || a.duplex === 'half');
            html += row('Link', (slow ? '<span class="warn">' : '') +
                esc((a.speed ? a.speed + ' Mbit/s' : (a.carrier ? 'up' : 'no cable')) + (a.duplex === 'half' ? ', half duplex' : '')) +
                (slow ? '</span>' : '') + esc(a.bus ? ' · ' + a.bus : ''));
            html += row('Address', esc(a.ip ? a.ip.replace(/\/\d+$/, '') : 'none yet'));
        } else {
            html += row('Adapter', 'none');
        }
        if (h.wifiFallbackOn) { html += row('Wi-Fi backup', '<span class="warn">on, the cable has no link</span>'); }
        if (s.speed && (s.speed.downMbps || s.speed.upMbps)) {
            html += row('Speed', esc((s.speed.downMbps || '?') + ' down · ' + (s.speed.upMbps || '?') + ' up Mbit/s' +
                (s.speed.pingMs !== null ? ' · ' + s.speed.pingMs + ' ms' : '')));
        }
        if (b) { html += row('Built-in port', esc(b.name + ' · ' + (b.carrier ? 'cable in' : 'no cable'))); }
        if (w) { html += row('Wi-Fi', w.carrier ? '<span class="warn">connected</span>' : 'off'); }
        var hookText = { enabled: 'on', disabled: 'off (disabled)', none: 'off', broken: 'broken link', legacy: 'old v1 hook', 'legacy-disabled': 'old v1 hook' }[h.state] || h.state;
        html += row('At boot', esc(hookText + (h.running ? ' · running' : '')));
        var last = s.log.length ? s.log[s.log.length - 1] : '';
        if (last) { html += row('Last log', esc(last)); }
        $('facts').innerHTML = html;

        // Notes (skip the first issue, already in the subline)
        var notes = issues.slice(1).concat(s.notes).slice(0, 4);
        $('notes').innerHTML = notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('');

        // Toggles
        var bootOn = h.state === 'enabled';
        $('tog-boot').className = 'tog' + (bootOn ? ' on' : '');
        $('tog-watch').className = 'tog' + (bootOn && h.watch ? ' on' : '');
        $('tog-wifi').className = 'tog' + (bootOn && h.wifiFallback ? ' on' : '');
        $('tog-updates').className = 'tog' + (bootOn && h.blockUpdates ? ' on' : '');
        var u = s.updates || {};
        $('updates-hint').textContent = u.hbcBlock === false ?
            (bootOn && h.blockUpdates ? 'also covers the Homebrew Channel\'s block, which is off' : 'the Homebrew Channel\'s block is off too') :
            'on top of the Homebrew Channel\'s block';
        // The faster-driver row only appears when it fits this TV: a driver is
        // known for this exact kernel and the adapter is one it supports, or a
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
        // A new driver to test: shown when there's one for this kernel, or a
        // past test's report to send
        var dt = s.driverTest || {};
        document.querySelector('[data-action="drvtest"]').style.display = dt.available || dt.result ? '' : 'none';
        $('drvtest-hint').textContent = dt.state === 'running' ? 'testing now' :
            (dt.result ? 'last test: ' + (DT_SAYS[dt.result] || dt.result) :
                (dt.adapterOk ? 'built for this TV\'s kernel, helps add support' : 'plug in an adapter it supports to try it'));
        renderUpdate();
        if (current >= buttons().length) { current = buttons().length - 1; }
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
        // Squeeze the rows a little when there are more of them, so they fit
        var n = buttons().length;
        $('actions').className = 'actions' + (n >= 10 ? ' tightest' : (n >= 9 ? ' tighter' : (n >= 8 ? ' tight' : '')));
        if (!show) { return; }
        $('update-title').textContent = 'Update to v' + upd.latest;
        $('update-hint').textContent = upd.source === 'homebrew' ? 'opens the Homebrew Channel' : 'you have v' + upd.current + ', downloads and installs';
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
            if (after) { after(ok, text); }
        });
    }

    // A step of a walk-through: an HTML list, OK goes on, BACK cancels
    function stepThen(title, html, hint, fn) {
        onConfirm = fn;
        overlay('confirm', title, html, hint);
    }
    function li(cls, html) { return '<li class="' + cls + '">' + html + '</li>'; }

    // CHANGELOG markdown, short: the bold lead if there is one, else the
    // first sentence.  Links become plain text, since there's no browser.
    function mdShort(s) {
        var b = s.match(/^\*\*(.+?)\*\*/);
        var t = b ? b[1] : s.replace(/^(.+?\.)\s.*$/, '$1');
        return esc(t.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1'))
            .replace(/`([^`]+)`/g, '<code>$1</code>');
    }

    // After an update, the first time the new version opens, show what
    // changed.  The last version seen is kept in the app's own storage.
    var whatsNewChecked = false;
    function whatsNew(s) {
        if (whatsNewChecked || !s) { return; }
        whatsNewChecked = true;
        var wn = window.LGU2E_WHATSNEW, v = s.version, seen = null;
        try {
            seen = window.localStorage.getItem('lgu2e.seenVersion');
            window.localStorage.setItem('lgu2e.seenVersion', v);
        } catch (e) { return; }
        // Updated in the app (the script logs it), or through the Homebrew Channel
        var updated = s.updatedTo === v || (seen && seen !== v);
        if (!updated || seen === v || !wn || wn.version !== v || overlayMode) { return; }
        var html = '', n = 0;
        wn.sections.forEach(function (sec) {
            if (n >= 7 || !sec.items.length) { return; }
            html += '<div class="walk-h">' + esc(sec.title) + '</div><ul class="walk">';
            sec.items.forEach(function (it) { if (n < 7) { html += li(sec.title === 'Fixed' ? 'ok' : '', mdShort(it)); n++; } });
            html += '</ul>';
        });
        overlay('message', 'Updated to v' + v + ': what\'s new', html,
            'Press OK or BACK to close.  Full notes: github.com/ohmybahgosh/LG-USB-2-ETH0/releases');
    }

    // Step 3 of the walk-through: upgrade, then check the result
    function upgradeNow() {
        busy = true;
        overlay('busy', 'Upgrade from v1', '<span class="step-of">Step 3 of 3 · upgrading</span><span class="spinner"></span>Replacing the boot hook…', '');
        runScript('install -y', function (ok, out, err) {
            refresh(function (s) {
                busy = false;
                var h = s ? s.hook : {};
                var done = ok && s && h.state === 'enabled' && !!h.link;
                var checks = '';
                if (s) {
                    checks += h.state === 'enabled' && h.link ? li('ok', 'The boot hook is this version\'s now: <code>' + esc(h.link) + '</code>') : li('warn', 'The boot hook isn\'t this version\'s yet.');
                    checks += h.state !== 'legacy' && h.state !== 'legacy-disabled' ? li('ok', 'The old v1 file is gone.') : li('warn', 'The old v1 file is still there.');
                    checks += s.adapter && s.adapterIsEth0 ? li('ok', 'Your USB adapter is still <code>eth0</code>.') : li('', 'The adapter becomes <code>eth0</code> at the next boot, or choose Switch now.');
                    checks += li('ok', 'Run at every boot is on.  Your settings are in <code>/var/lib/webosbrew/lg-usb-2-eth0.conf</code>.');
                }
                var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim().split('\n').slice(-8).join('\n');
                overlay('message', done ? 'Upgrade from v1: done' : 'Upgrade from v1: something went wrong',
                    '<span class="step-of">Step 3 of 3 · ' + (done ? 'all done' : 'check this') + '</span><ul class="walk">' + checks + '</ul>' +
                    (done ? '' : '<pre>' + esc(text) + '</pre>'),
                    done ? 'Press OK or BACK to close.  Nothing else to do.' : 'Press OK or BACK to close.  Report for GitHub makes a report you can send.');
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
            var said = result === 'works' ? 'It works!  ' : (result === 'crashed' ? 'The TV restarted during the test, so this driver doesn\'t fit as it is.  ' : '');
            var html = '<div class="qr">' + svg + '<div>' + esc(said) + 'Scan this with your phone to send the result on GitHub, already filled in.  ' +
                'Every result helps, good or bad.  MAC and IP addresses are left out.<br><br><pre>' +
                esc(report.split('\n').slice(0, 10).join('\n')) + '</pre></div></div>';
            if (again) {
                stepThen('Driver test: ' + (DT_SAYS[result] || result), html, 'Press OK to test again, or BACK to close.', drvtestStart);
            } else {
                overlay('message', 'Driver test: ' + (DT_SAYS[result] || result), html,
                    result === 'works' ? 'Press OK or BACK to close.  The driver stays in use until the next restart.' : 'Press OK or BACK to close.');
            }
        });
    }

    // Start a test, then follow it until it's done (it runs detached, since
    // moving the adapter takes the network down for a moment)
    function drvtestStart() {
        var dt = (state && state.driverTest) || {};
        if (!dt.adapterOk) {
            overlay('message', 'Test a new driver', 'Plug in a USB adapter with a chip the new driver is for first: Realtek (RTL8152, RTL8153, and on newer TVs RTL8156), or ASIX AX88179 on 2020 TVs with the K6Lp chip.', 'Press OK or BACK to close.');
            return;
        }
        confirmThen('Test a new driver?',
            'There\'s a driver built for this TV\'s kernel from LG\'s own source, that hasn\'t run on a TV with this kernel yet.  ' +
            'The test downloads it, checks its checksum, loads it until the next restart only, moves the adapter to it and checks it gets online.  ' +
            'The network drops for a moment.  If it doesn\'t fit, the TV can freeze or restart: restart it (unplug it if needed) and open the app again to send that result too.',
            function () {
                busy = true;
                overlay('busy', 'Testing the new driver', '<span class="spinner"></span>Downloading and checking it, then moving the adapter over.  This takes up to a minute.', '');
                runScript('test-driver -y --no-wait', function (ok, out, err) {
                    var tries = 0;
                    function poll() {
                        refresh(function (s) {
                            var st = s && s.driverTest ? s.driverTest.state : '';
                            if (st === 'running' && tries++ < 40) { setTimeout(poll, 3000); return; }
                            busy = false;
                            if (st === 'done') { drvtestResult(false); return; }
                            var text = (out || err || '').replace(/\x1b\[[0-9;]*m/g, '').trim().split('\n').slice(-12).join('\n');
                            overlay('message', st === 'running' ? 'Driver test: still running' : 'Driver test: didn\'t start',
                                '<pre>' + esc(text) + '</pre>', 'Press OK or BACK to close.');
                        });
                    }
                    setTimeout(poll, 2000);
                });
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
                var page = (state.driverPage || '').replace(/^https:\/\//, '');
                confirmThen('Use the faster driver?',
                    'This downloads a driver module built for this exact TV kernel' + (page ? ' by ' + page.split('/')[1] + ' (' + page + ')' : '') + ', checks its checksum, and loads it at every boot.  ' +
                    'Moving the adapter to it takes the network down for a moment.  Wi-Fi is a good way back in if anything goes wrong.',
                    function () {
                        act('Faster driver', 'get-driver -y && sh ' + shq(SCRIPT) + ' ' + installArgs('--module ' + shq(state.driverFile)) +
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
            act(on ? 'Stop following plug and unplug' : 'Follow plug and unplug', installArgs(on ? '--no-watch' : '--watch'));
        },
        wifi: function () {
            if (!state) { return; }
            var on = state.hook.state === 'enabled' && state.hook.wifiFallback;
            if (on) {
                act('Wi-Fi backup off', installArgs('--no-wifi-fallback'));
            } else {
                confirmThen('Use Wi-Fi as a backup?',
                    'If eth0 loses its cable link for a minute while Wi-Fi is off, the TV turns Wi-Fi on and joins a network it already knows.  ' +
                    'Once the cable works again, Wi-Fi goes back off, so traffic returns to the adapter.  Starts from the next boot.',
                    function () { act('Wi-Fi backup', installArgs('--wifi-fallback')); });
            }
        },
        updates: function () {
            if (!state) { return; }
            if (state.hook.state === 'enabled' && state.hook.blockUpdates) {
                confirmThen('Stop blocking updates harder?',
                    'webOS\'s own update check goes back to how it was, and the extra servers and the firewall rule come off.  The Homebrew Channel\'s Block system updates stays as it is.',
                    function () { act('Update blocking off', installArgs('--no-block-updates')); });
            } else {
                confirmThen('Block updates harder?',
                    'A firmware update can remove root for good, and LG\'s current firmware, webOS 26 included, can\'t be rooted again.  ' +
                    'It turns off webOS\'s own update check, blocks LG\'s update servers (the ones the Homebrew Channel\'s Block system updates covers, if that\'s off, and the ones it misses), and the one the updater reaches by IP.  ' +
                    'It starts now and at every boot, and turning it off undoes all of it.',
                    function () { act('Block updates', installArgs('--block-updates')); });
            }
        },
        apply: function () {
            confirmThen('Switch now?', 'The network drops for a few seconds while the adapter becomes eth0.', function () {
                act('Switch now', 'apply -y', null, true);
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
                li('warn', 'A v1 boot hook you turned off is still in the boot folder, as <code>' + hookDir + 'S01fix-eth.disabled</code>.  On many TVs that file still runs at every boot.') :
                li('warn', 'The v1 boot hook is installed, at <code>' + hookDir + 'S01fix-eth</code>.  It runs at every boot and renames <code>eth0</code> even when no adapter is plugged in.');
            var adapter = s.adapter && s.adapterIsEth0 ? li('ok', 'Your USB adapter is <code>eth0</code> right now.') :
                (s.adapter ? li('', 'Your USB adapter is plugged in, as <code>' + esc(s.adapter.name) + '</code>.') : li('', 'No USB adapter is plugged in right now.'));
            stepThen('Upgrade from v1', '<span class="step-of">Step 1 of 3 · what\'s there now</span><ul class="walk">' + found + adapter +
                li('', 'The upgrade takes a few seconds and doesn\'t touch the network.') + '</ul>',
                'Press OK to see what changes, or BACK to cancel.', function () {
                    stepThen('Upgrade from v1', '<span class="step-of">Step 2 of 3 · what changes</span><ul class="walk">' +
                        li('ok', 'The v1 hook is replaced, in place, by this version\'s: a link to the script inside this app, so updating the app updates the hook too.') +
                        li('ok', 'Nothing switches now.  The adapter stays as it is until the next boot.') +
                        li('ok', 'At boot, the new hook only changes anything when an adapter is plugged in, and puts the old names back if a step fails.') +
                        li('', 'It starts with the defaults.  Turn on Faster driver, Follow plug and unplug or Wi-Fi as a backup afterwards if you want them.') +
                        li('', wasOff ? 'This turns the boot hook on.  Prefer it off?  Turn off Run at every boot afterwards.' : 'To undo everything later, use Turn everything off.') + '</ul>',
                        'Press OK to upgrade, or BACK to cancel.', upgradeNow);
                });
        },
        update: function () {
            if (!upd || !upd.newer) { return; }
            if (upd.source === 'homebrew') {
                luna('luna://com.webos.applicationManager/launch', { id: 'org.webosbrew.hbchannel' }, function () {});
                return;
            }
            confirmThen('Update to v' + upd.latest + '?',
                'Downloads the new version from GitHub, checks its SHA-256, and installs it.  The app closes and opens again by itself.  Your settings stay as they are.',
                function () {
                    act('Update', 'update -y', function (ok, text) {
                        // What's new shows once the new version opens, not here
                        if (ok && /Installing/.test(text || '')) {
                            overlay('message', 'Updating to v' + upd.latest,
                                '<span class="spinner"></span>Checked the download and installing it now.  The app closes and opens again by itself in a few seconds, then shows what\'s new.', '');
                        }
                    });
                });
        },
        speed: function () {
            if (busy) { return; }
            busy = true;
            var r = { pingMs: null, downMbps: null, upMbps: null, server: '', interface: '' };
            function tile(label, value, unit, running) {
                return '<div class="tile' + (running ? ' run' : '') + '"><small>' + label + '</small>' +
                    (value === null ? '<b class="wait">' + (running ? '…' : '–') + '</b>' : '<b>' + esc(String(value)) + '</b>') +
                    '<span>' + unit + '</span></div>';
            }
            function draw(stage, done) {
                var where = r.interface ? 'Over ' + r.interface + (r.server ? ', to Cloudflare\'s ' + r.server + ' server' : ', to Cloudflare') + '.' : 'Finding the nearest Cloudflare server…';
                overlay(done ? 'message' : 'busy', done ? 'Speed test' : 'Speed test: ' + stage,
                    '<div class="speed">' + tile('Download', r.downMbps, 'Mbit/s', stage === 'download') +
                    tile('Upload', r.upMbps, 'Mbit/s', stage === 'upload') + tile('Latency', r.pingMs, 'ms', stage === 'latency') +
                    '</div><div class="speed-meta">' + esc(where) + '  Uses a few hundred MB of data.</div>',
                    done ? 'Press OK or BACK to close.' : 'This takes about 15 seconds.');
            }
            function fail(text) {
                busy = false;
                overlay('message', 'Speed test: something went wrong',
                    '<pre>' + esc((text || 'No answer from the script.').replace(/\x1b\[[0-9;]*m/g, '').trim()) + '</pre>', 'Press OK or BACK to close.');
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
                        draw('', true);
                        refresh();
                    });
                });
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
    refresh(whatsNew);
    checkUpdate();
}());
