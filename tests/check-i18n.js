// Every text the TV app shows in English has a translation in each language
// of webos-app/src/i18n.js, and the translations keep the {placeholders}.
//
//   node tests/check-i18n.js
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = path.join(__dirname, '../webos-app/src');
const app = fs.readFileSync(path.join(SRC, 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(SRC, 'index.html'), 'utf8');

// Load i18n.js the way the TV does, with no saved choice
const box = { window: {}, navigator: { language: 'en-US' }, document: {} };
box.window.localStorage = { getItem: () => null, setItem: () => {} };
vm.runInNewContext(fs.readFileSync(path.join(SRC, 'i18n.js'), 'utf8'), box);
const I = box.window.LGU2E_I18N;

// Texts app.js passes to T() or TC() as a literal
const used = new Set();
const lit = /\bTC?\(\s*'((?:[^'\\]|\\.)*)'/g;
let m;
while ((m = lit.exec(app))) { used.add(m[1].replace(/\\'/g, "'")); }
// Texts it passes through a variable: the driver test's results, the speed
// test's stages, and the CHANGELOG headings What's new shows
const says = app.match(/var DT_SAYS = \{([\s\S]*?)\};/);
if (!says) { console.log('DT_SAYS not found in app.js'); process.exit(1); }
const vals = says[1].match(/:\s*'((?:[^'\\]|\\.)*)'/g).map((v) => v.replace(/^:\s*'|'$/g, '').replace(/\\'/g, "'"));
vals.forEach((t) => used.add(t));
['latency', 'download', 'upload', 'Added', 'Fixed', 'Changed', 'Auto ({lang})'].forEach((t) => used.add(t));
// index.html's own text, between tags
html.replace(/<script[\s\S]*?<\/script>/g, '').replace(/>([^<>]+)</g, (all, t) => {
  t = t.trim();
  if (t && /[A-Za-z]/.test(t) && !/^(LG-USB-2-ETH0|OK|BACK|github\.com\/\S+)$/.test(t)) { used.add(t); }
  return all;
});

let bad = 0;
const ph = (s) => (s.match(/\{\w+\}/g) || []).sort().join(',');
for (const [lang, dict] of Object.entries(I.dicts)) {
  for (const t of used) {
    if (!Object.prototype.hasOwnProperty.call(dict, t)) { console.log(`missing ${lang}: ${JSON.stringify(t)}`); bad++; }
    else if (ph(t) !== ph(dict[t])) { console.log(`placeholders differ ${lang}: ${JSON.stringify(t)}`); bad++; }
  }
  for (const t of Object.keys(dict)) {
    if (!used.has(t)) { console.log(`unused ${lang}: ${JSON.stringify(t)}`); }
  }
  console.log(`${lang}: ${used.size} texts, ${bad ? bad + ' problems' : 'all translated'}`);
}
// The script's status messages (and the pieces some are built from), with
// made-up values in place of the variables: each must come out with no
// English sentence left in it
const sh = fs.readFileSync(path.join(__dirname, '../LG-USB-2-ETH0.sh'), 'utf8');
const msgs = [];
const re = /(?:status_issue|status_note|_hx=|_rx=|SIG_MSG=)\s*"((?:[^"\\]|\\.)*)"/g;
while ((m = re.exec(sh))) { msgs.push(m[1]); }
const fill = (t) => t
  .replace(/\$_hx|\$_rx|\$SIG_MSG/g, '')
  .replace(/\$DRIVER_DIR\/\$\(echo\s*$/, "/var/lib/webosbrew/lg-usb-2-eth0-drivers/r8152_oot.ko'.")
  .replace(/\$\(uname -r\)/g, '5.4.268-329.ptl4tv.5')
  .replace(/\$\{WIFI_BACK_SECS\}/g, '60').replace(/\$_spd/g, '100').replace(/\$LOG_FILE/g, '/var/lib/webosbrew/lg-usb-2-eth0.log')
  .replace(/\$_chip/g, 'Microchip LAN78xx').replace(/\$_id/g, '0424:7800')
  .replace(/\$\{_\w+:-[^}]*\}|\$_\w+|\$[A-Z_]+/g, 'eth1')
  .replace(/\\"/g, '"');
const OK = /Block system updates|Homebrew Channel|sh \/home\/root\/r8152-autobind\.sh uninstall|Busybox run-parts|LG-USB-2-ETH0|Microchip LAN78xx/g;
// In a language with another alphabet, any run of three Latin words is left
// over English.  In one with the same alphabet, English's small words are
// the tell: none of these is a word in Spanish
const latinRun = /[A-Za-z']{2,}(?:\s+[A-Za-z'.-]{2,}){2,}/;
const smallWords = /\b(the|is|are|was|it|it's|its|this|that|and|but|or|to|of|on|in|with|your|for|run|has|have|isn't|won't|didn't|can|may|still|not|yet|only|which|when|after|from|there|so|because|again|now)\b/i;
const latinScript = (lang) => /[A-Za-z]/.test(I.names[lang] || '');
for (const [lang] of Object.entries(I.scripts)) {
  const english = latinScript(lang) ? smallWords : latinRun;
  let n = 0;
  for (const raw of msgs) {
    const t = fill(raw).trim();
    if (!t) { continue; }
    n++;
    // With this language's patterns, whatever language i18n.js picked here
    let r = t;
    for (const [rx, to] of I.scripts[lang]) { r = r.replace(rx, to); }
    if (english.test(r.replace(OK, ''))) { console.log(`script message not translated (${lang}): ${t}\n  -> ${r}`); bad++; }
  }
  console.log(`${lang}: ${n} script messages checked`);
}
// The boot hook's messages on the TV, in the script itself
const toasts = (sh.match(/^toast_text\(\) \{[\s\S]*?^\}/m) || [''])[0];
for (const k of (toasts.match(/\*:([a-z-]+)\)/g) || []).map((x) => x.slice(2, -1))) {
  for (const lang of Object.keys(I.dicts)) {
    if (toasts.indexOf(`${lang}:${k})`) < 0) { console.log(`toast ${k} has no ${lang} text in toast_text()`); bad++; }
  }
}

// English stays English, and placeholders fill in
if (I.T('Update to v{v}', { v: '2.8.0' }) !== 'Update to v2.8.0') { console.log('T() placeholder fill broken'); bad++; }
process.exit(bad ? 1 : 0);
