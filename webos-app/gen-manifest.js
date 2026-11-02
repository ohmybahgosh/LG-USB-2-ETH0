// Write the Homebrew Channel manifest for one built IPK.
// Usage: node gen-manifest.js <appinfo.json> <ipk> <out dir>
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const [appinfoFile, ipk, outDir] = process.argv.slice(2);
const app = JSON.parse(fs.readFileSync(appinfoFile, 'utf8'));
const data = fs.readFileSync(ipk);
const repo = 'https://github.com/ohmybahgosh/LG-USB-2-ETH0';

const manifest = {
  id: app.id,
  version: app.version,
  type: app.type,
  title: app.title,
  appDescription: app.appDescription,
  iconUri: `https://raw.githubusercontent.com/ohmybahgosh/LG-USB-2-ETH0/main/webos-app/src/icon160.png`,
  sourceUrl: repo,
  rootRequired: true,
  ipkUrl: `${repo}/releases/download/v${app.version}/${path.basename(ipk)}`,
  ipkHash: { sha256: crypto.createHash('sha256').update(data).digest('hex') },
  ipkSize: data.length,
};
const out = path.join(outDir, `${app.id}.manifest.json`);
fs.writeFileSync(out, JSON.stringify(manifest, null, 2) + '\n');
console.log(`Wrote ${out}`);
