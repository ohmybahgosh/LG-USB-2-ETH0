// Write whatsnew.js for the TV app: this version's section of CHANGELOG.md,
// as { version, sections: [{ title, items: [markdown] }], i18n: { ru: [...] } }.
// The same section from each translated changelog (docs/changelog.ru.md and
// so on) goes in i18n, so What's new shows in the app's language.
// Usage: node gen-whatsnew.js <CHANGELOG.md> <version> <out file> [lang=changelog ...]
'use strict';
const fs = require('fs');

// One version's sections from a changelog, or null when it has none
function parse(changelog, version) {
  let text;
  try { text = fs.readFileSync(changelog, 'utf8'); } catch (e) { return null; }
  const sections = [];
  let on = false;
  let cur = null;
  for (const line of text.split('\n')) {
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
  return sections.length ? sections : null;
}

if (require.main === module) {
  const [changelog, version, out, ...langs] = process.argv.slice(2);
  const sections = parse(changelog, version);
  let data = null;
  if (sections) {
    data = { version, sections, i18n: {} };
    for (const arg of langs) {
      const [lang, file] = arg.split('=');
      const s = parse(file, version);
      if (s) { data.i18n[lang] = s; } else { console.log(`No ${lang} section for ${version} in ${file}: What's new shows in English there`); }
    }
  }
  fs.writeFileSync(out, '// Made by gen-whatsnew.js from CHANGELOG.md\nwindow.LGU2E_WHATSNEW = ' + JSON.stringify(data, null, 2) + ';\n');
  console.log(data ? `Wrote ${out}` : `No CHANGELOG section for ${version}; ${out} is empty`);
}

module.exports = { parse };
