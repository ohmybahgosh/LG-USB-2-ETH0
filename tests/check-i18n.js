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
// English stays English, and placeholders fill in
if (I.T('Update to v{v}', { v: '2.8.0' }) !== 'Update to v2.8.0') { console.log('T() placeholder fill broken'); bad++; }
process.exit(bad ? 1 : 0);
