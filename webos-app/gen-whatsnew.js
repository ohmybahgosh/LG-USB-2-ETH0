// Write whatsnew.js for the TV app: this version's section of CHANGELOG.md,
// as { version, sections: [{ title, items: [markdown] }] }.
// Usage: node gen-whatsnew.js <CHANGELOG.md> <version> <out file>
'use strict';
const fs = require('fs');

const [changelog, version, out] = process.argv.slice(2);
const lines = fs.readFileSync(changelog, 'utf8').split('\n');
const sections = [];
let on = false;
let cur = null;
for (const line of lines) {
  if (/^## /.test(line)) {
    if (on) { break; }
    on = line.startsWith('## [' + version + ']');
    continue;
  }
  if (!on) { continue; }
  const h = line.match(/^### (.+)/);
  if (h) { cur = { title: h[1].trim(), items: [] }; sections.push(cur); continue; }
  const i = line.match(/^- (.+)/);
  if (i && cur) { cur.items.push(i[1].trim()); continue; }
  // An item that wraps onto the next line
  if (cur && cur.items.length && /^ {2}\S/.test(line)) { cur.items[cur.items.length - 1] += ' ' + line.trim(); }
}
const data = sections.length ? { version, sections } : null;
fs.writeFileSync(out, '// Made by gen-whatsnew.js from CHANGELOG.md\nwindow.LGU2E_WHATSNEW = ' + JSON.stringify(data, null, 2) + ';\n');
console.log(data ? `Wrote ${out}` : `No CHANGELOG section for ${version}; ${out} is empty`);
